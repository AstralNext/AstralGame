//! 本机游戏进程 + UDP 监听口（Windows Win32，无 PowerShell）。

#[derive(Clone, Debug)]
pub struct GameProcessInfo {
    pub pid: u32,
    pub exe: String,
    pub title: String,
    pub path: String,
    pub udp_ports: Vec<u16>,
}

/// 按 exe 名或窗口标题过滤进程，并列出其 UDP 口。
pub fn list_game_processes(
    exe_names: Vec<String>,
    window_needles: Vec<String>,
) -> Vec<GameProcessInfo> {
    #[cfg(target_os = "windows")]
    {
        windows_impl::list_game_processes(&exe_names, &window_needles)
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = (exe_names, window_needles);
        Vec::new()
    }
}

#[cfg(target_os = "windows")]
mod windows_impl {
    use super::GameProcessInfo;
    use flutter_rust_bridge::frb;
    use std::collections::HashMap;
    use std::ffi::OsString;
    use std::os::windows::ffi::OsStringExt;
    use windows::core::PWSTR;
    use windows::Win32::Foundation::{BOOL, HWND, LPARAM, CloseHandle};
    use windows::Win32::NetworkManagement::IpHelper::{
        GetExtendedUdpTable, MIB_UDPROW_OWNER_PID, MIB_UDPTABLE_OWNER_PID, UDP_TABLE_OWNER_PID,
    };
    use windows::Win32::System::Diagnostics::ToolHelp::{
        CreateToolhelp32Snapshot, Process32FirstW, Process32NextW, PROCESSENTRY32W,
        TH32CS_SNAPPROCESS,
    };
    use windows::Win32::System::Threading::{
        OpenProcess, QueryFullProcessImageNameW, PROCESS_QUERY_LIMITED_INFORMATION,
    };
    use windows::Win32::UI::WindowsAndMessaging::{
        EnumWindows, GetWindowTextW, GetWindowThreadProcessId, IsWindowVisible,
    };

    const AF_INET: u32 = 2;

    #[frb(ignore)]
    pub(super) fn list_game_processes(
        exe_names: &[String],
        window_needles: &[String],
    ) -> Vec<GameProcessInfo> {
        let exes: Vec<String> = exe_names
            .iter()
            .map(|s| s.trim().to_ascii_lowercase())
            .filter(|s| !s.is_empty())
            .collect();
        let needles: Vec<String> = window_needles
            .iter()
            .map(|s| s.trim().to_lowercase())
            .filter(|s| !s.is_empty())
            .collect();
        if exes.is_empty() && needles.is_empty() {
            return Vec::new();
        }

        let titles = window_titles();
        let udp_by_pid = udp_ports_by_pid();
        let mut out = Vec::new();

        let snapshot = unsafe { CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0) };
        let Ok(snapshot) = snapshot else {
            return out;
        };
        if snapshot.is_invalid() {
            return out;
        }

        let mut entry = PROCESSENTRY32W {
            dwSize: std::mem::size_of::<PROCESSENTRY32W>() as u32,
            ..Default::default()
        };
        let mut ok = unsafe { Process32FirstW(snapshot, &mut entry) }.is_ok();
        while ok {
            let pid = entry.th32ProcessID;
            let exe = wchar_to_string(&entry.szExeFile).to_ascii_lowercase();
            let title = titles.get(&pid).cloned().unwrap_or_default();
            let exe_hit = exes.iter().any(|e| exe == *e);
            let title_hit = !title.is_empty()
                && needles
                    .iter()
                    .any(|n| title.to_lowercase().contains(n));
            if exe_hit || title_hit {
                let mut ports = udp_by_pid.get(&pid).cloned().unwrap_or_default();
                ports.sort_unstable();
                ports.dedup();
                out.push(GameProcessInfo {
                    pid,
                    exe,
                    title,
                    path: process_image_path(pid),
                    udp_ports: ports,
                });
            }
            ok = unsafe { Process32NextW(snapshot, &mut entry) }.is_ok();
        }
        unsafe {
            let _ = CloseHandle(snapshot);
        }
        out
    }

    fn wchar_to_string(buf: &[u16]) -> String {
        let len = buf.iter().position(|&c| c == 0).unwrap_or(buf.len());
        OsString::from_wide(&buf[..len])
            .to_string_lossy()
            .into_owned()
    }

    fn process_image_path(pid: u32) -> String {
        unsafe {
            let handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
            let Ok(handle) = handle else {
                return String::new();
            };
            if handle.is_invalid() {
                return String::new();
            }
            let mut buf = [0u16; 512];
            let mut size = buf.len() as u32;
            let ok = QueryFullProcessImageNameW(
                handle,
                Default::default(),
                PWSTR(buf.as_mut_ptr()),
                &mut size,
            )
            .is_ok();
            let _ = CloseHandle(handle);
            if !ok {
                return String::new();
            }
            wchar_to_string(&buf[..size as usize])
        }
    }

    fn udp_ports_by_pid() -> HashMap<u32, Vec<u16>> {
        let mut size = 0u32;
        unsafe {
            GetExtendedUdpTable(
                None,
                &mut size,
                true,
                AF_INET,
                UDP_TABLE_OWNER_PID,
                0,
            );
        }
        if size == 0 {
            return HashMap::new();
        }
        let mut buf = vec![0u8; size as usize];
        let err = unsafe {
            GetExtendedUdpTable(
                Some(buf.as_mut_ptr() as *mut _),
                &mut size,
                true,
                AF_INET,
                UDP_TABLE_OWNER_PID,
                0,
            )
        };
        if err != 0 {
            return HashMap::new();
        }
        let table = unsafe { &*(buf.as_ptr() as *const MIB_UDPTABLE_OWNER_PID) };
        let row_size = std::mem::size_of::<MIB_UDPROW_OWNER_PID>();
        let header = std::mem::size_of::<u32>();
        let max_rows = buf.len().saturating_sub(header) / row_size.max(1);
        let count = (table.dwNumEntries as usize).min(max_rows);
        let rows = unsafe {
            std::slice::from_raw_parts(table.table.as_ptr(), count)
        };
        let mut map: HashMap<u32, Vec<u16>> = HashMap::new();
        for row in rows {
            let port = u16::from_be((row.dwLocalPort & 0xFFFF) as u16);
            if port == 0 {
                continue;
            }
            // 只保留 0.0.0.0 监听口。连上玩家后的 connected UDP 会绑在具体网卡 IP 上。
            if row.dwLocalAddr != 0 {
                continue;
            }
            map.entry(row.dwOwningPid).or_default().push(port);
        }
        map
    }

    struct TitleSink {
        map: HashMap<u32, String>,
    }

    fn window_titles() -> HashMap<u32, String> {
        let mut sink = TitleSink {
            map: HashMap::new(),
        };
        unsafe {
            let _ = EnumWindows(Some(enum_windows_proc), LPARAM(&mut sink as *mut _ as isize));
        }
        sink.map
    }

    unsafe extern "system" fn enum_windows_proc(hwnd: HWND, lparam: LPARAM) -> BOOL {
        let sink = &mut *(lparam.0 as *mut TitleSink);
        if !IsWindowVisible(hwnd).as_bool() {
            return BOOL(1);
        }
        let mut pid = 0u32;
        GetWindowThreadProcessId(hwnd, Some(&mut pid));
        if pid == 0 {
            return BOOL(1);
        }
        let mut buf = [0u16; 512];
        let n = GetWindowTextW(hwnd, &mut buf);
        if n <= 0 {
            return BOOL(1);
        }
        let title = wchar_to_string(&buf[..n as usize]);
        if title.is_empty() {
            return BOOL(1);
        }
        sink.map
            .entry(pid)
            .and_modify(|old| {
                if title.len() > old.len() {
                    *old = title.clone();
                }
            })
            .or_insert(title);
        BOOL(1)
    }
}
