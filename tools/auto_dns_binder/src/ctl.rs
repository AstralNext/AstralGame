use std::ffi::OsString;
use std::io;
use std::thread;
use std::time::{Duration, Instant};

use windows_service::service::{
    ServiceAccess, ServiceDependency, ServiceErrorControl, ServiceInfo, ServiceStartType,
    ServiceState, ServiceType,
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
    let dest_dir = paths::program_data_dir();
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

fn upsert_binder_service() -> Result<(), String> {
    let manager = manager(
        ServiceManagerAccess::CONNECT
            | ServiceManagerAccess::CREATE_SERVICE
            | ServiceManagerAccess::ENUMERATE_SERVICE,
    )
    .map_err(fmt_svc)?;

    if let Ok(existing) = manager.open_service(
        paths::SERVICE_NAME,
        ServiceAccess::CHANGE_CONFIG | ServiceAccess::QUERY_STATUS | ServiceAccess::STOP,
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
        log::info(&format!(
            "updated existing service {}",
            paths::SERVICE_NAME
        ));
        return Ok(());
    }

    let service = manager
        .create_service(
            &service_info(),
            ServiceAccess::CHANGE_CONFIG | ServiceAccess::QUERY_STATUS,
        )
        .map_err(fmt_svc)?;
    service
        .set_description(paths::SERVICE_DESCRIPTION)
        .map_err(fmt_svc)?;
    log::info(&format!("service {} installed", paths::SERVICE_NAME));
    Ok(())
}

pub fn install() -> Result<(), String> {
    let _ = std::fs::create_dir_all(paths::program_data_dir());
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

    let dir = paths::program_data_dir();
    if dir.is_dir() {
        match remove_dir_best_effort(&dir) {
            Ok(()) => log::info(&format!("removed {}", dir.display())),
            Err(err) => log::warn(&format!(
                "could not fully remove {}: {err}",
                dir.display()
            )),
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
