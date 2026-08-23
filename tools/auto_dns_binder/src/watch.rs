use std::time::Duration;

use windows::Win32::Foundation::{CloseHandle, HANDLE, WAIT_FAILED, WAIT_OBJECT_0};
use windows::Win32::NetworkManagement::IpHelper::{CancelIPChangeNotify, NotifyAddrChange};
use windows::Win32::System::IO::OVERLAPPED;
use windows::Win32::System::Threading::{
    CreateEventW, ResetEvent, WaitForMultipleObjects, INFINITE,
};

use crate::dns::{self, AdapterState};
use crate::log;

const ERROR_IO_PENDING: u32 = 997;

pub struct AddrWatcher {
    stop_event: HANDLE,
    addr_event: HANDLE,
    overlapped: OVERLAPPED,
    notify_handle: HANDLE,
    known_ips: AdapterState,
}

impl AddrWatcher {
    pub fn new(stop_event: HANDLE) -> windows::core::Result<Self> {
        unsafe {
            let addr_event = CreateEventW(None, true, false, None)?;
            Ok(Self {
                stop_event,
                addr_event,
                overlapped: OVERLAPPED::default(),
                notify_handle: HANDLE::default(),
                known_ips: AdapterState::new(),
            })
        }
    }

    pub fn apply_initial(&mut self) {
        if let Some(state) = dns::get_all_physical_ips() {
            for (guid, (friendly_name, ips)) in &state {
                log::info(&format!("physical NIC [{friendly_name}] ips={ips:?}"));
                dns::bind_local_smartdns(guid);
            }
            self.known_ips = state;
        } else {
            log::warn("no physical NIC is up at start");
        }
    }

    pub fn arm(&mut self) -> bool {
        unsafe {
            self.overlapped = OVERLAPPED {
                hEvent: self.addr_event,
                ..OVERLAPPED::default()
            };
            let _ = ResetEvent(self.addr_event);
            self.notify_handle = HANDLE::default();
            let code = NotifyAddrChange(&mut self.notify_handle, &self.overlapped);
            if code == 0 || code == ERROR_IO_PENDING {
                true
            } else {
                log::error(&format!("NotifyAddrChange failed, Win32 error {code}"));
                false
            }
        }
    }

    /// Wait until stop is signaled (`true`) or an address-table change arrives (`false`).
    pub fn wait_stop_or_change(&self) -> bool {
        unsafe {
            let handles = [self.stop_event, self.addr_event];
            let wait = WaitForMultipleObjects(&handles, false, INFINITE);
            if wait == WAIT_OBJECT_0 {
                return true;
            }
            if wait.0 == WAIT_OBJECT_0.0 + 1 {
                return false;
            }
            if wait == WAIT_FAILED {
                log::error("WaitForMultipleObjects failed");
            }
            false
        }
    }

    pub fn on_addr_change(&mut self) {
        std::thread::sleep(Duration::from_millis(1500));
        let Some(current) = dns::get_all_physical_ips() else {
            return;
        };
        for (guid, (friendly_name, current_ips)) in &current {
            let last_ips = self
                .known_ips
                .get(guid)
                .map(|(_, ips)| ips.clone())
                .unwrap_or_default();
            if current_ips != &last_ips {
                log::info(&format!(
                    "IP changed on [{friendly_name}] {last_ips:?} -> {current_ips:?}"
                ));
                dns::bind_local_smartdns(guid);
                self.known_ips
                    .insert(guid.clone(), (friendly_name.clone(), current_ips.clone()));
            }
        }
        self.known_ips = current;
    }

    pub fn cancel(&mut self) {
        unsafe {
            let _ = CancelIPChangeNotify(&self.overlapped);
        }
    }
}

impl Drop for AddrWatcher {
    fn drop(&mut self) {
        self.cancel();
        unsafe {
            if !self.addr_event.is_invalid() {
                let _ = CloseHandle(self.addr_event);
            }
        }
    }
}
