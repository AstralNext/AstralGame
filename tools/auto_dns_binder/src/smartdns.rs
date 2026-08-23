use std::fs;
use std::io;
use std::os::windows::process::CommandExt;
use std::process::{Command, Output, Stdio};

use crate::log;
use crate::paths;

const CREATE_NO_WINDOW: u32 = 0x0800_0000;

pub fn run_cli(args: &[&str]) -> Result<Output, String> {
    let exe = paths::find_smartdns_exe().ok_or_else(|| {
        "找不到 smartdns.exe。请确认已随包提供 native/dns/smartdns/smartdns.exe。".to_string()
    })?;
    let output = Command::new(&exe)
        .args(args)
        .stdin(Stdio::null())
        .creation_flags(CREATE_NO_WINDOW)
        .output()
        .map_err(|err| format!("启动 smartdns 失败: {err}"))?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    if !stdout.trim().is_empty() {
        log::info(&format!("smartdns {args:?}: {}", stdout.trim()));
    }
    if !stderr.trim().is_empty() {
        log::info(&format!("smartdns {args:?} err: {}", stderr.trim()));
    }
    Ok(output)
}

fn cli_ok(args: &[&str]) -> Result<(), String> {
    let output = run_cli(args)?;
    if output.status.success() {
        Ok(())
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);
        Err(format!(
            "smartdns {args:?} 失败: {} {}",
            stdout.trim(),
            stderr.trim()
        ))
    }
}

/// `smartdns.exe service install`；已安装则忽略错误。
pub fn install_official_service() -> Result<(), String> {
    match cli_ok(&["service", "install"]) {
        Ok(()) => Ok(()),
        Err(err) => {
            log::warn(&format!("smartdns service install: {err}"));
            Ok(())
        }
    }
}

pub fn deploy_conf() -> io::Result<()> {
    let src_dir = paths::find_smartdns_src_dir().ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::NotFound,
            "找不到 smartdns.conf 源目录",
        )
    })?;
    let src_conf = src_dir.join(paths::SMARTDNS_CONF_NAME);
    if !src_conf.is_file() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!("missing {}", src_conf.display()),
        ));
    }
    let dest_dir = paths::smartdns_conf_dir();
    fs::create_dir_all(&dest_dir)?;
    fs::copy(&src_conf, paths::smartdns_conf_path())?;
    log::info(&format!(
        "copied {} -> {}",
        src_conf.display(),
        paths::smartdns_conf_path().display()
    ));
    Ok(())
}

pub fn restart_service() -> Result<(), String> {
    if cli_ok(&["service", "restart"]).is_ok() {
        return Ok(());
    }
    let _ = run_cli(&["service", "stop"]);
    cli_ok(&["service", "start"])
}

pub fn uninstall_official_service() -> Result<(), String> {
    match cli_ok(&["service", "uninstall", "--purge"]) {
        Ok(()) => Ok(()),
        Err(err) => {
            log::warn(&format!("smartdns service uninstall: {err}"));
            Ok(())
        }
    }
}
