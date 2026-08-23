use std::ffi::OsString;
use std::sync::mpsc;
use std::time::Duration;

use windows::Win32::System::Threading::{CreateEventW, SetEvent};
use windows_service::define_windows_service;
use windows_service::service::{
    ServiceControl, ServiceControlAccept, ServiceExitCode, ServiceState, ServiceStatus, ServiceType,
};
use windows_service::service_control_handler::{self, ServiceControlHandlerResult};
use windows_service::service_dispatcher;

use crate::log;
use crate::paths;
use crate::watch::AddrWatcher;

const SERVICE_TYPE: ServiceType = ServiceType::OWN_PROCESS;

define_windows_service!(ffi_service_main, service_main);

pub fn run_dispatcher() -> windows_service::Result<()> {
    service_dispatcher::start(paths::SERVICE_NAME, ffi_service_main)
}

fn service_main(_arguments: Vec<OsString>) {
    if let Err(err) = run_service() {
        log::error(&format!("service stopped with error: {err}"));
    }
}

fn run_service() -> Result<(), String> {
    let stop_event = unsafe {
        CreateEventW(None, true, false, None).map_err(|err| format!("CreateEventW: {err}"))?
    };
    let stop_for_handler = stop_event;

    let (tx, rx) = mpsc::channel::<()>();
    let event_handler = move |control_event| -> ServiceControlHandlerResult {
        match control_event {
            ServiceControl::Stop | ServiceControl::Shutdown | ServiceControl::Preshutdown => {
                let _ = unsafe { SetEvent(stop_for_handler) };
                let _ = tx.send(());
                ServiceControlHandlerResult::NoError
            }
            ServiceControl::Interrogate => ServiceControlHandlerResult::NoError,
            _ => ServiceControlHandlerResult::NotImplemented,
        }
    };

    let status_handle = service_control_handler::register(paths::SERVICE_NAME, event_handler)
        .map_err(|err| format!("{err}"))?;

    status_handle
        .set_service_status(ServiceStatus {
            service_type: SERVICE_TYPE,
            current_state: ServiceState::StartPending,
            controls_accepted: ServiceControlAccept::empty(),
            exit_code: ServiceExitCode::Win32(0),
            checkpoint: 1,
            wait_hint: Duration::from_secs(10),
            process_id: None,
        })
        .map_err(|err| format!("{err}"))?;

    let _ = std::fs::create_dir_all(paths::program_data_dir());
    log::init(paths::log_file());
    log::info("service starting");

    let mut watcher = AddrWatcher::new(stop_event).map_err(|err| format!("{err}"))?;
    watcher.apply_initial();
    if !watcher.arm() {
        log::warn("addr watch arm failed; retrying in loop");
    }

    status_handle
        .set_service_status(running_status())
        .map_err(|err| format!("{err}"))?;

    loop {
        if rx.try_recv().is_ok() {
            break;
        }
        if watcher.wait_stop_or_change() {
            break;
        }
        watcher.on_addr_change();
        if !watcher.arm() {
            std::thread::sleep(Duration::from_secs(5));
            let _ = watcher.arm();
        }
    }

    watcher.cancel();
    log::info("service stopping");

    status_handle
        .set_service_status(ServiceStatus {
            service_type: SERVICE_TYPE,
            current_state: ServiceState::Stopped,
            controls_accepted: ServiceControlAccept::empty(),
            exit_code: ServiceExitCode::Win32(0),
            checkpoint: 0,
            wait_hint: Duration::default(),
            process_id: None,
        })
        .map_err(|err| format!("{err}"))?;
    Ok(())
}

fn running_status() -> ServiceStatus {
    ServiceStatus {
        service_type: SERVICE_TYPE,
        current_state: ServiceState::Running,
        controls_accepted: ServiceControlAccept::STOP
            | ServiceControlAccept::SHUTDOWN
            | ServiceControlAccept::PRESHUTDOWN,
        exit_code: ServiceExitCode::Win32(0),
        checkpoint: 0,
        wait_hint: Duration::default(),
        process_id: None,
    }
}
