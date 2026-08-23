use std::env;
use std::path::PathBuf;

/// Windows 服务内部名 / SCM 名称。
pub const SERVICE_NAME: &str = "AstralGameAutoDnsBinder";
/// 服务控制台显示名。
pub const SERVICE_DISPLAY_NAME: &str = "Astral Game Auto DNS Binder";
pub const SERVICE_DESCRIPTION: &str =
    "Listen for physical NIC IP changes and bind DNS to local SmartDNS.";

/// smartdns-rs `service install` 注册的 SCM 名。
pub const SMARTDNS_SERVICE_NAME: &str = "smartdns-rs";
pub const SMARTDNS_PROGRAM_FILES: &str = r"C:\Program Files\SmartDNS\smartdns.exe";

pub const INSTALLED_EXE_NAME: &str = "auto_dns_binder.exe";
pub const SMARTDNS_EXE_NAME: &str = "smartdns.exe";
pub const SMARTDNS_CONF_NAME: &str = "smartdns.conf";

pub fn install_dir() -> PathBuf {
    let root = env::var_os("ProgramW6432")
        .or_else(|| env::var_os("ProgramFiles"))
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(r"C:\Program Files"));
    root.join("AstralGameAutoDnsBinder")
}

/// 旧版误装到 ProgramData 的目录，卸载时一并清掉。
pub fn legacy_program_data_dir() -> PathBuf {
    let root = env::var_os("ProgramData")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(r"C:\ProgramData"));
    root.join("AstralGameAutoDnsBinder")
}

pub fn installed_exe() -> PathBuf {
    install_dir().join(INSTALLED_EXE_NAME)
}

pub fn log_file() -> PathBuf {
    install_dir().join("service.log")
}

pub fn smartdns_conf_dir() -> PathBuf {
    let root = env::var_os("ProgramData")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(r"C:\ProgramData"));
    root.join("smartdns")
}

pub fn smartdns_conf_path() -> PathBuf {
    smartdns_conf_dir().join(SMARTDNS_CONF_NAME)
}

/// 安装时查找旁边的 smartdns 目录（`native/dns/smartdns` 或仓库 `tools/smartdns`）。
pub fn find_smartdns_src_dir() -> Option<PathBuf> {
    let exe_dir = env::current_exe().ok()?.parent()?.to_path_buf();
    let candidates = [
        exe_dir.join("smartdns"),
        exe_dir.clone(),
        exe_dir.join("..").join("smartdns"),
        exe_dir.join("..").join("..").join("..").join("smartdns"),
    ];
    candidates
        .into_iter()
        .find(|dir| dir.join(SMARTDNS_EXE_NAME).is_file())
}

pub fn find_smartdns_exe() -> Option<PathBuf> {
    if let Some(dir) = find_smartdns_src_dir() {
        let bundled = dir.join(SMARTDNS_EXE_NAME);
        if bundled.is_file() {
            return Some(bundled);
        }
    }
    let installed = PathBuf::from(SMARTDNS_PROGRAM_FILES);
    installed.is_file().then_some(installed)
}
