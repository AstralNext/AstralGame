use std::ffi::OsString;
use std::io;
use std::thread;
use std::time::{Duration, Instant};

use windows_service::service::{
    ServiceAccess, ServiceAction, ServiceActionType, ServiceDependency, ServiceErrorControl,
    ServiceFailureActions, ServiceFailureResetPeriod, ServiceInfo, ServiceStartType, ServiceState,
    ServiceType,
};
use windows_service::service_manager::{ServiceManager, ServiceManagerAccess};

use crate::dns;
use crate::log;
use crate::paths;
use crate::smartdns;

fn manager(access: ServiceManagerAccess) -> windows_service::Result<ServiceManager> {
    ServiceManager::local_computer(None::<&str>, access)
}

fn service_info() -> ServiceInfo {
    ServiceInfo {
        name: OsString::from(paths::SERVICE_NAME),
        display_name: OsString::from(paths::SERVICE_DISPLAY_NAME),
        service_type: ServiceType::OWN_PROCESS,
        start_type: ServiceStartType::AutoStart,
        error_control: ServiceErrorControl::Normal,
        executable_path: paths::installed_exe(),
        launch_arguments: vec![],
        dependencies: vec![ServiceDependency::Service(OsString::from(
            paths::SMARTDNS_SERVICE_NAME,
        ))],
        account_name: None,
        account_password: None,
    }
}

fn wait_state(want: ServiceState, timeout: Duration) -> windows_service::Result<ServiceState> {
    let manager = manager(ServiceManagerAccess::CONNECT)?;
    let service = manager.open_service(paths::SERVICE_NAME, ServiceAccess::QUERY_STATUS)?;
    let start = Instant::now();
    loop {
        let status = service.query_status()?;
        if status.current_state == want {
            return Ok(status.current_state);
        }
        if start.elapsed() > timeout {
            return Ok(status.current_state);
        }
        thread::sleep(Duration::from_millis(200));
    }
}

fn copy_self_exe() -> io::Result<()> {
    let dest_dir = paths::install_dir();
    fs_create(&dest_dir)?;
    let src_exe = std::env::current_exe()?;
    let dest_exe = paths::installed_exe();
    if src_exe.canonicalize().ok() != dest_exe.canonicalize().ok() {
        std::fs::copy(&src_exe, &dest_exe)?;
    }
    Ok(())
}

fn fs_create(dir: &std::path::Path) -> io::Result<()> {
    std::fs::create_dir_all(dir)
}

fn configure_restart_on_failure(
    service: &windows_service::service::Service,
) -> windows_service::Result<()> {
    let restart = ServiceAction {
        action_type: ServiceActionType::Restart,
        delay: Duration::from_secs(5),
    };
    service.update_failure_actions(ServiceFailureActions {
        reset_period: ServiceFailureResetPeriod::Never,
        reboot_msg: None,
        command: None,
        actions: Some(vec![restart.clone(), restart.clone(), restart]),
    })?;
    service.set_failure_actions_on_non_crash_failures(true)?;
    Ok(())
}

fn upsert_binder_service() -> Result<(), String> {
    let manager = manager(
        ServiceManagerAccess::CONNECT
            | ServiceManagerAccess::CREATE_SERVICE
            | ServiceManagerAccess::ENUMERATE_SERVICE,
    )
    .map_err(fmt_svc)?;

    if let Ok(existing) = manager.open_service(
        paths::SERVICE_NAME,
        ServiceAccess::CHANGE_CONFIG
            | ServiceAccess::QUERY_STATUS
            | ServiceAccess::STOP
            | ServiceAccess::START,
    ) {
        let state = existing.query_status().map_err(fmt_svc)?.current_state;
        if state != ServiceState::Stopped {
            let _ = existing.stop();
            let _ = wait_state(ServiceState::Stopped, Duration::from_secs(15));
        }
        existing.change_config(&service_info()).map_err(fmt_svc)?;
        existing
            .set_description(paths::SERVICE_DESCRIPTION)
            .map_err(fmt_svc)?;
        configure_restart_on_failure(&existing).map_err(fmt_svc)?;
        log::info(&format!(
            "updated existing service {} (restart on failure)",
            paths::SERVICE_NAME
        ));
        return Ok(());
    }

    let service = manager
        .create_service(
            &service_info(),
            ServiceAccess::CHANGE_CONFIG | ServiceAccess::QUERY_STATUS | ServiceAccess::START,
        )
        .map_err(fmt_svc)?;
    service
        .set_description(paths::SERVICE_DESCRIPTION)
        .map_err(fmt_svc)?;
    configure_restart_on_failure(&service).map_err(fmt_svc)?;
    log::info(&format!(
        "service {} installed (restart on failure)",
        paths::SERVICE_NAME
    ));
    Ok(())
}

pub fn install() -> Result<(), String> {
    let _ = std::fs::create_dir_all(paths::install_dir());
    smartdns::install_official_service()?;
    smartdns::deploy_conf().map_err(|err| format!("复制 smartdns.conf 失败: {err}"))?;
    smartdns::restart_service()?;
    copy_self_exe().map_err(|err| format!("复制 auto_dns_binder 失败: {err}"))?;
    upsert_binder_service()?;
    start()?;
    log::info("network optimize stack installed");
    Ok(())
}

pub fn uninstall() -> Result<(), String> {
    let _ = stop();
    dns::clear_all_physical_to_dhcp();

    let manager = manager(ServiceManagerAccess::CONNECT).map_err(fmt_svc)?;
    match manager.open_service(
        paths::SERVICE_NAME,
        ServiceAccess::QUERY_STATUS | ServiceAccess::STOP | ServiceAccess::DELETE,
    ) {
        Ok(service) => {
            let state = service.query_status().map_err(fmt_svc)?.current_state;
            if state != ServiceState::Stopped {
                let _ = service.stop();
                let _ = wait_state(ServiceState::Stopped, Duration::from_secs(20));
            }
            drop(service);
            let service = manager
                .open_service(paths::SERVICE_NAME, ServiceAccess::DELETE)
                .map_err(fmt_svc)?;
            service.delete().map_err(fmt_svc)?;
            log::info(&format!("service {} deleted", paths::SERVICE_NAME));
        }
        Err(_) => log::warn("binder service is not installed"),
    }

    for dir in [paths::install_dir(), paths::legacy_program_data_dir()] {
        if dir.is_dir() {
            match remove_dir_best_effort(&dir) {
                Ok(()) => log::info(&format!("removed {}", dir.display())),
                Err(err) => log::warn(&format!(
                    "could not fully remove {}: {err}",
                    dir.display()
                )),
            }
        }
    }

    smartdns::uninstall_official_service()?;
    log::info("network optimize stack uninstalled");
    Ok(())
}

fn remove_dir_best_effort(dir: &std::path::Path) -> io::Result<()> {
    match std::fs::remove_dir_all(dir) {
        Ok(()) => Ok(()),
        Err(err) => {
            thread::sleep(Duration::from_millis(400));
            std::fs::remove_dir_all(dir).or(Err(err))
        }
    }
}

pub fn start() -> Result<(), String> {
    let manager = manager(ServiceManagerAccess::CONNECT).map_err(fmt_svc)?;
    let service = manager
        .open_service(
            paths::SERVICE_NAME,
            ServiceAccess::START | ServiceAccess::QUERY_STATUS,
        )
        .map_err(fmt_svc)?;
    let state = service.query_status().map_err(fmt_svc)?.current_state;
    if state == ServiceState::Running {
        log::info("service already running");
        return Ok(());
    }
    service.start(&[] as &[&str]).map_err(fmt_svc)?;
    let state = wait_state(ServiceState::Running, Duration::from_secs(20)).map_err(fmt_svc)?;
    log::info(&format!("service state: {state:?}"));
    Ok(())
}

pub fn stop() -> Result<(), String> {
    let manager = manager(ServiceManagerAccess::CONNECT).map_err(fmt_svc)?;
    let service = manager
        .open_service(
            paths::SERVICE_NAME,
            ServiceAccess::STOP | ServiceAccess::QUERY_STATUS,
        )
        .map_err(fmt_svc)?;
    let state = service.query_status().map_err(fmt_svc)?.current_state;
    if state == ServiceState::Stopped {
        log::info("service already stopped");
        return Ok(());
    }
    service.stop().map_err(fmt_svc)?;
    let state = wait_state(ServiceState::Stopped, Duration::from_secs(20)).map_err(fmt_svc)?;
    log::info(&format!("service state: {state:?}"));
    Ok(())
}

pub fn restart() -> Result<(), String> {
    let _ = stop();
    start()
}

/// 轮询指定 SCM 服务是否进入 Running（最多等 [timeout]）。
fn service_running(name: &str, timeout: Duration) -> bool {
    let Ok(manager) = manager(ServiceManagerAccess::CONNECT) else {
        return false;
    };
    let start = Instant::now();
    loop {
        let running = manager
            .open_service(name, ServiceAccess::QUERY_STATUS)
            .ok()
            .and_then(|service| service.query_status().ok())
            .is_some_and(|status| status.current_state == ServiceState::Running);
        if running {
            return true;
        }
        if start.elapsed() > timeout {
            return false;
        }
        thread::sleep(Duration::from_millis(300));
    }
}

/// 用外部文件替换 SmartDNS 配置并重启服务；新配置起不来则回滚到上一版。
///
/// 客户端（Flutter 侧）把远端下发的 `smartdns.conf` 落到临时文件后调这里，
/// 由本服务负责写 `%ProgramData%\smartdns` 与重启服务，客户端不直接碰。
pub fn deploy_conf_from(src: &std::path::Path) -> Result<(), String> {
    if !src.is_file() {
        return Err(format!("配置源文件不存在: {}", src.display()));
    }
    let incoming = std::fs::read(src).map_err(|err| format!("读取配置源失败: {err}"))?;
    if incoming.is_empty() {
        return Err("配置源为空，已忽略".to_string());
    }

    let dest = paths::smartdns_conf_path();
    if let Some(parent) = dest.parent() {
        fs_create(parent).map_err(|err| format!("创建配置目录失败: {err}"))?;
    }

    // 内容一致就别白重启一次 DNS。
    if std::fs::read(&dest).is_ok_and(|current| current == incoming) {
        log::info("smartdns.conf 无变化，跳过");
        return Ok(());
    }

    let backup = dest.with_extension("conf.bak");
    if dest.is_file() {
        std::fs::copy(&dest, &backup).map_err(|err| format!("备份旧配置失败: {err}"))?;
    }
    std::fs::copy(src, &dest).map_err(|err| format!("写入新配置失败: {err}"))?;
    log::info(&format!("已部署 {}", dest.display()));

    let _ = smartdns::restart_service();
    if service_running(paths::SMARTDNS_SERVICE_NAME, Duration::from_secs(10)) {
        log::info("新配置已生效");
        return Ok(());
    }

    log::warn("新配置未能启动 SmartDNS，回滚到上一版");
    if backup.is_file() {
        std::fs::copy(&backup, &dest).map_err(|err| format!("回滚配置失败: {err}"))?;
        let _ = smartdns::restart_service();
        let _ = service_running(paths::SMARTDNS_SERVICE_NAME, Duration::from_secs(10));
    }
    Err("新配置未能启动 SmartDNS，已回滚".to_string())
}

pub fn status() -> Result<(), String> {
    let manager = manager(ServiceManagerAccess::CONNECT).map_err(fmt_svc)?;
    match manager.open_service(paths::SERVICE_NAME, ServiceAccess::QUERY_STATUS) {
        Ok(service) => {
            let status = service.query_status().map_err(fmt_svc)?;
            println!("installed=yes");
            println!("state={:?}", status.current_state);
            Ok(())
        }
        Err(_) => {
            println!("installed=no");
            println!("state=not_installed");
            Ok(())
        }
    }
}

fn fmt_svc(err: windows_service::Error) -> String {
    format!("{err}")
}
