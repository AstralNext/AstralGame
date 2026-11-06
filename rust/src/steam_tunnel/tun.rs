//! wintun L3 虚拟网卡：创建/复用适配器、配置 IPv4、收发包线程。
//!
//! 网卡名固定 `AstralSteam`，使用固定 GUID，这样第二次建房时 `Adapter::open`
//! 能直接复用同一块网卡，避免 Windows 里堆积一堆虚拟适配器。

use std::net::Ipv4Addr;
use std::sync::mpsc::{self, Receiver};
use std::sync::Arc;
use std::thread;

use wintun::{Adapter, Session, MAX_RING_CAPACITY};

pub const ADAPTER_NAME: &str = "AstralSteam";
/// 固定 GUID：让重复建房复用同一块网卡。
const ADAPTER_GUID: u128 = 0x1f6a_5a27_0b7c_4d19_9a54_04b1_5c8e_2d31;

pub struct TunRoom {
    pub session: Arc<Session>,
    /// 仅用于保持适配器活着：Session 释放后适配器仍可复用，但过早 drop 会
    /// 让下一次建房重新创建网卡。
    #[allow(dead_code)]
    pub adapter: Arc<Adapter>,
    pub rx: Receiver<Vec<u8>>,
}

impl TunRoom {
    /// 把一帧 IP 包写回虚拟网卡（等于让本机协议栈收到这个包）。
    pub fn inject(&self, packet: &[u8]) -> bool {
        if packet.is_empty() || packet.len() > u16::MAX as usize {
            return false;
        }
        let Ok(mut send) = self.session.allocate_send_packet(packet.len() as u16) else {
            return false;
        };
        send.bytes_mut().copy_from_slice(packet);
        self.session.send_packet(send);
        true
    }

    pub fn shutdown(&self) {
        let _ = self.session.shutdown();
    }
}

pub fn open(ip: Ipv4Addr, mtu: usize) -> Result<TunRoom, String> {
    open_named(ip, mtu, ADAPTER_NAME, ADAPTER_GUID, "Astral Steam")
}

/// 以指定网卡名 / GUID 打开虚拟网卡。
///
/// 组网驱动使用独立网卡，避免与 EasyTier 复用同一适配器。
pub fn open_named(
    ip: Ipv4Addr,
    mtu: usize,
    adapter_name: &str,
    adapter_guid: u128,
    adapter_desc: &str,
) -> Result<TunRoom, String> {
    let wintun = load_wintun()
        .map_err(|e| format!("加载 wintun.dll 失败（请确认程序目录存在 wintun.dll）: {e}"))?;

    let adapter = match Adapter::open(&wintun, adapter_name) {
        Ok(a) => a,
        Err(_) => Adapter::create(&wintun, adapter_name, adapter_desc, Some(adapter_guid))
            .map_err(|e| format!("创建虚拟网卡失败（需要管理员权限）: {e}"))?,
    };

    let name = adapter
        .get_name()
        .map_err(|e| format!("读取网卡名失败: {e}"))?;
    set_mtu(&name, mtu)?;
    configure_interface(&name, ip)?;

    let session = Arc::new(
        adapter
            .start_session(MAX_RING_CAPACITY)
            .map_err(|e| format!("启动网卡会话失败: {e}"))?,
    );

    let (tx, rx) = mpsc::channel::<Vec<u8>>();
    let reader = session.clone();
    thread::Builder::new()
        .name("astral-steam-tun".to_string())
        .spawn(move || {
            // shutdown() 或被驱动打断时 receive_blocking 返回 Err，循环随之结束。
            while let Ok(packet) = reader.receive_blocking() {
                let bytes = packet.bytes().to_vec();
                drop(packet);
                if tx.send(bytes).is_err() {
                    break;
                }
            }
        })
        .map_err(|e| format!("启动网卡读线程失败: {e}"))?;

    Ok(TunRoom {
        session,
        adapter,
        rx,
    })
}

fn load_wintun() -> Result<wintun::Wintun, String> {
    // 正常发行版把 wintun.dll 放在 exe 同目录，LoadLibrary 默认搜索路径即可。
    if let Ok(w) = unsafe { wintun::load() } {
        return Ok(w);
    }
    let exe_dir = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|d| d.to_path_buf()));
    let mut candidates = Vec::new();
    if let Some(dir) = exe_dir {
        candidates.push(dir.join("wintun.dll"));
        candidates.push(dir.join("dlls").join("wintun.dll"));
        candidates.push(dir.join("data").join("wintun.dll"));
    }
    candidates.push(std::path::PathBuf::from("wintun.dll"));
    candidates.push(std::path::PathBuf::from("dlls/wintun.dll"));
    for path in candidates {
        if path.exists() {
            if let Ok(w) = unsafe { wintun::load_from_path(&path) } {
                return Ok(w);
            }
        }
    }
    Err("未找到可用的 wintun.dll".to_string())
}

/// 配置网卡地址与跃点。wintun 默认自动跃点 5，会把 100.100.100.x 的流量
/// 排到物理网卡后面；压到 0 才能保证虚拟局域网优先。
fn configure_interface(name: &str, ip: Ipv4Addr) -> Result<(), String> {
    let set_addr = netsh(&[
        "interface",
        "ipv4",
        "set",
        "address",
        &format!("name=\"{name}\""),
        "static",
        &ip.to_string(),
        "255.255.255.0",
    ]);
    if !set_addr {
        return Err(format!("配置虚拟网卡地址失败（需要管理员权限）: {ip}"));
    }
    let _ = netsh(&[
        "interface",
        "ipv4",
        "set",
        "interface",
        &format!("interface=\"{name}\""),
        "metric=0",
    ]);
    Ok(())
}

/// 设置网卡 MTU。
///
/// wintun 0.5.1 的 `Adapter::set_mtu` 内部直接 `Command::new("netsh").output()`，
/// 没有传 `CREATE_NO_WINDOW`；本程序是 GUI 进程，子进程会新开一个控制台窗口，
/// 表现为建房时闪一次黑框。这里改成自己调用带隐藏标志的 netsh。
fn set_mtu(name: &str, mtu: usize) -> Result<(), String> {
    let ok = netsh(&[
        "interface",
        "ipv4",
        "set",
        "subinterface",
        &format!("\"{name}\""),
        &format!("mtu={mtu}"),
        "store=persistent",
    ]);
    if ok {
        Ok(())
    } else {
        Err(format!("设置网卡 MTU 失败: {mtu}"))
    }
}

/// 执行 netsh（隐藏控制台窗口，避免 GUI 进程弹黑框）。
fn netsh(args: &[&str]) -> bool {
    use std::os::windows::process::CommandExt;
    use std::process::Command;
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    Command::new("netsh.exe")
        .creation_flags(CREATE_NO_WINDOW)
        .args(args)
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}
