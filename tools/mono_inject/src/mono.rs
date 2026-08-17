#![cfg(windows)]

use std::ffi::c_void;
use std::mem::{size_of, transmute};
use std::ptr::null_mut;
use std::thread;
use std::time::{Duration, Instant};
use windows::Win32::Foundation::{CloseHandle, HANDLE, HMODULE, WAIT_OBJECT_0};
use windows::Win32::System::Diagnostics::Debug::{ReadProcessMemory, WriteProcessMemory};
use windows::Win32::System::Diagnostics::ToolHelp::{
    CreateToolhelp32Snapshot, Process32FirstW, Process32NextW, PROCESSENTRY32W, TH32CS_SNAPPROCESS,
};
use windows::Win32::System::Memory::{
    VirtualAllocEx, VirtualFreeEx, MEM_COMMIT, MEM_RELEASE, PAGE_EXECUTE_READWRITE,
};
use windows::Win32::System::ProcessStatus::{
    K32EnumProcessModulesEx, K32GetModuleFileNameExW, K32GetModuleInformation, LIST_MODULES_ALL,
    MODULEINFO,
};
use windows::Win32::System::Threading::{
    CreateRemoteThread, IsWow64Process, OpenProcess, WaitForSingleObject, INFINITE,
    PROCESS_ALL_ACCESS,
};

const MONO_EXPORTS: &[&str] = &[
    "mono_get_root_domain",
    "mono_thread_attach",
    "mono_image_open_from_data",
    "mono_assembly_load_from_full",
    "mono_assembly_get_image",
    "mono_class_from_name",
    "mono_class_get_method_from_name",
    "mono_runtime_invoke",
    "mono_assembly_close",
    "mono_image_strerror",
    "mono_object_get_class",
    "mono_class_get_name",
];

pub fn pids_by_name(name: &str) -> Vec<u32> {
    let want = name.trim().trim_end_matches(".exe").to_ascii_lowercase();
    let mut out = Vec::new();
    unsafe {
        let snap = match CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0) {
            Ok(h) => h,
            Err(_) => return out,
        };
        if snap.is_invalid() {
            return out;
        }
        let mut entry = PROCESSENTRY32W {
            dwSize: size_of::<PROCESSENTRY32W>() as u32,
            ..Default::default()
        };
        let mut ok = Process32FirstW(snap, &mut entry).is_ok();
        while ok {
            let exe = wchar_to_string(&entry.szExeFile)
                .trim_end_matches(".exe")
                .to_ascii_lowercase();
            if exe == want {
                out.push(entry.th32ProcessID);
            }
            ok = Process32NextW(snap, &mut entry).is_ok();
        }
        let _ = CloseHandle(snap);
    }
    out
}

pub fn inject(
    pid: u32,
    assembly: &[u8],
    namespace: &str,
    class: &str,
    method: &str,
) -> Result<(), String> {
    if assembly.is_empty() {
        return Err("assembly is empty".into());
    }
    crate::log::info(&format!(
        "inject pid={pid} bytes={} invoke={namespace}.{class}.{method}",
        assembly.len()
    ));
    unsafe {
        let handle = OpenProcess(PROCESS_ALL_ACCESS, false, pid).map_err(|e| {
            let msg = format!("OpenProcess pid={pid}: {e} (try run as admin?)");
            crate::log::error(&msg);
            msg
        })?;
        crate::log::info(&format!("OpenProcess ok pid={pid}"));
        let result = (|| {
            if !is_64bit(handle) {
                return Err("32-bit Unity is not supported".into());
            }
            crate::log::info("wait mono.dll (max 45s)");
            let mono = wait_for_mono(handle)?;
            crate::log::info(&format!("mono.dll base=0x{mono:x}"));
            let exports = resolve_exports(handle, mono)?;
            crate::log::info("mono exports ok");
            let mut mem = RemoteMemory::new(handle);
            let root = call(
                &mut mem,
                &exports,
                exports.addr("mono_get_root_domain")?,
                &[],
                None,
            )?;
            if root == 0 {
                return Err("mono_get_root_domain returned 0".into());
            }
            crate::log::info(&format!("root domain=0x{root:x}"));
            let status = mem.alloc(4)?;
            let raw = mem.write_bytes(assembly)?;
            let image = call(
                &mut mem,
                &exports,
                exports.addr("mono_image_open_from_data")?,
                &[raw, assembly.len() as u64, 1, status],
                Some(root),
            )?;
            if image == 0 || mem.read_i32(status)? != 0 {
                return Err("mono_image_open_from_data failed".into());
            }
            crate::log::info(&format!("image=0x{image:x}"));
            let dummy = mem.write_bytes(&[0u8])?;
            let status2 = mem.alloc(4)?;
            let asm_ptr = call(
                &mut mem,
                &exports,
                exports.addr("mono_assembly_load_from_full")?,
                &[image, dummy, status2, 0],
                Some(root),
            )?;
            if asm_ptr == 0 || mem.read_i32(status2)? != 0 {
                return Err("mono_assembly_load_from_full failed".into());
            }
            crate::log::info(&format!("assembly=0x{asm_ptr:x}"));
            let img = call(
                &mut mem,
                &exports,
                exports.addr("mono_assembly_get_image")?,
                &[asm_ptr],
                Some(root),
            )?;
            if img == 0 {
                return Err("mono_assembly_get_image returned 0".into());
            }
            let ns = mem.write_cstr(namespace)?;
            let cls = mem.write_cstr(class)?;
            let klass = call(
                &mut mem,
                &exports,
                exports.addr("mono_class_from_name")?,
                &[img, ns, cls],
                Some(root),
            )?;
            if klass == 0 {
                return Err(format!("class not found: {namespace}.{class}"));
            }
            let mname = mem.write_cstr(method)?;
            let method_ptr = call(
                &mut mem,
                &exports,
                exports.addr("mono_class_get_method_from_name")?,
                &[klass, mname, 0],
                Some(root),
            )?;
            if method_ptr == 0 {
                return Err(format!("method not found: {method}"));
            }
            crate::log::info(&format!("invoke {namespace}.{class}.{method}"));
            let exc = mem.write_u64(0)?;
            let _ = call(
                &mut mem,
                &exports,
                exports.addr("mono_runtime_invoke")?,
                &[method_ptr, 0, 0, exc],
                Some(root),
            )?;
            crate::log::info(&format!("invoke returned ok pid={pid}"));
            Ok(())
        })();
        let _ = CloseHandle(handle);
        if let Err(ref err) = result {
            crate::log::error(&format!("inject failed pid={pid}: {err}"));
        }
        result
    }
}

struct Exports {
    map: Vec<(String, u64)>,
}

impl Exports {
    fn addr(&self, name: &str) -> Result<u64, String> {
        self.map
            .iter()
            .find(|(n, _)| n == name)
            .map(|(_, a)| *a)
            .ok_or_else(|| format!("export missing: {name}"))
    }
}

struct RemoteMemory {
    handle: HANDLE,
    allocs: Vec<u64>,
}

impl RemoteMemory {
    fn new(handle: HANDLE) -> Self {
        Self {
            handle,
            allocs: Vec::new(),
        }
    }

    fn alloc(&mut self, size: usize) -> Result<u64, String> {
        unsafe {
            let ptr = VirtualAllocEx(
                self.handle,
                None,
                size.max(16),
                MEM_COMMIT,
                PAGE_EXECUTE_READWRITE,
            );
            if ptr.is_null() {
                return Err("VirtualAllocEx failed".into());
            }
            let addr = ptr as u64;
            self.allocs.push(addr);
            Ok(addr)
        }
    }

    fn write_bytes(&mut self, data: &[u8]) -> Result<u64, String> {
        let addr = self.alloc(data.len())?;
        self.write(addr, data)?;
        Ok(addr)
    }

    fn write_cstr(&mut self, s: &str) -> Result<u64, String> {
        let mut buf = s.as_bytes().to_vec();
        buf.push(0);
        self.write_bytes(&buf)
    }

    fn write_u64(&mut self, value: u64) -> Result<u64, String> {
        self.write_bytes(&value.to_le_bytes())
    }

    fn write(&self, addr: u64, data: &[u8]) -> Result<(), String> {
        unsafe {
            WriteProcessMemory(
                self.handle,
                addr as *const c_void,
                data.as_ptr() as *const c_void,
                data.len(),
                Some(null_mut()),
            )
            .map_err(|e| format!("WriteProcessMemory: {e}"))?;
        }
        Ok(())
    }

    fn read(&self, addr: u64, size: usize) -> Result<Vec<u8>, String> {
        let mut buf = vec![0u8; size];
        unsafe {
            ReadProcessMemory(
                self.handle,
                addr as *const c_void,
                buf.as_mut_ptr() as *mut c_void,
                size,
                Some(null_mut()),
            )
            .map_err(|e| format!("ReadProcessMemory: {e}"))?;
        }
        Ok(buf)
    }

    fn read_i32(&self, addr: u64) -> Result<i32, String> {
        let b = self.read(addr, 4)?;
        Ok(i32::from_le_bytes(b.try_into().unwrap()))
    }

    fn read_u32(&self, addr: u64) -> Result<u32, String> {
        let b = self.read(addr, 4)?;
        Ok(u32::from_le_bytes(b.try_into().unwrap()))
    }

    fn read_u16(&self, addr: u64) -> Result<u16, String> {
        let b = self.read(addr, 2)?;
        Ok(u16::from_le_bytes(b.try_into().unwrap()))
    }

    fn read_cstr(&self, addr: u64, max: usize) -> Result<String, String> {
        let bytes = self.read(addr, max)?;
        let end = bytes.iter().position(|&b| b == 0).unwrap_or(bytes.len());
        Ok(String::from_utf8_lossy(&bytes[..end]).into_owned())
    }
}

impl Drop for RemoteMemory {
    fn drop(&mut self) {
        unsafe {
            for addr in &self.allocs {
                let _ = VirtualFreeEx(self.handle, *addr as *mut c_void, 0, MEM_RELEASE);
            }
        }
    }
}

fn call(
    mem: &mut RemoteMemory,
    exports: &Exports,
    fn_addr: u64,
    args: &[u64],
    attach_root: Option<u64>,
) -> Result<u64, String> {
    let ret = mem.write_u64(0)?;
    let code = assemble64(fn_addr, ret, args, attach_root, exports)?;
    let code_addr = mem.write_bytes(&code)?;
    unsafe {
        let start = transmute(code_addr as usize);
        let thread = CreateRemoteThread(mem.handle, None, 0, start, None, Default::default(), None)
            .map_err(|e| format!("CreateRemoteThread: {e}"))?;
        let wait = WaitForSingleObject(thread, INFINITE);
        let _ = CloseHandle(thread);
        if wait != WAIT_OBJECT_0 {
            return Err("WaitForSingleObject failed".into());
        }
    }
    let out = mem.read(ret, 8)?;
    Ok(u64::from_le_bytes(out.try_into().unwrap()))
}

fn assemble64(
    fn_addr: u64,
    ret_addr: u64,
    args: &[u64],
    attach_root: Option<u64>,
    exports: &Exports,
) -> Result<Vec<u8>, String> {
    let mut asm = Vec::new();
    emit(&mut asm, &[0x48, 0x83, 0xEC, 0x28]); // sub rsp, 40
    if let Some(root) = attach_root {
        let attach = exports.addr("mono_thread_attach")?;
        emit_mov_rax(&mut asm, attach);
        emit_mov_rcx(&mut asm, root);
        emit(&mut asm, &[0xFF, 0xD0]); // call rax
    }
    emit_mov_rax(&mut asm, fn_addr);
    for (i, arg) in args.iter().take(4).enumerate() {
        match i {
            0 => emit_mov_rcx(&mut asm, *arg),
            1 => emit_mov_rdx(&mut asm, *arg),
            2 => emit_mov_r8(&mut asm, *arg),
            3 => emit_mov_r9(&mut asm, *arg),
            _ => {}
        }
    }
    emit(&mut asm, &[0xFF, 0xD0]); // call rax
    emit(&mut asm, &[0x48, 0x83, 0xC4, 0x28]); // add rsp, 40
    emit(&mut asm, &[0x48, 0xA3]); // mov [imm64], rax
    asm.extend_from_slice(&ret_addr.to_le_bytes());
    emit(&mut asm, &[0xC3]); // ret
    Ok(asm)
}

fn emit(asm: &mut Vec<u8>, bytes: &[u8]) {
    asm.extend_from_slice(bytes);
}

fn emit_mov_rax(asm: &mut Vec<u8>, value: u64) {
    emit(asm, &[0x48, 0xB8]);
    asm.extend_from_slice(&value.to_le_bytes());
}

fn emit_mov_rcx(asm: &mut Vec<u8>, value: u64) {
    emit(asm, &[0x48, 0xB9]);
    asm.extend_from_slice(&value.to_le_bytes());
}

fn emit_mov_rdx(asm: &mut Vec<u8>, value: u64) {
    emit(asm, &[0x48, 0xBA]);
    asm.extend_from_slice(&value.to_le_bytes());
}

fn emit_mov_r8(asm: &mut Vec<u8>, value: u64) {
    emit(asm, &[0x49, 0xB8]);
    asm.extend_from_slice(&value.to_le_bytes());
}

fn emit_mov_r9(asm: &mut Vec<u8>, value: u64) {
    emit(asm, &[0x49, 0xB9]);
    asm.extend_from_slice(&value.to_le_bytes());
}

fn is_64bit(handle: HANDLE) -> bool {
    let mut wow = windows::Win32::Foundation::BOOL(0);
    unsafe {
        if IsWow64Process(handle, &mut wow).is_err() {
            return true;
        }
    }
    wow.0 == 0
}

fn wait_for_mono(handle: HANDLE) -> Result<u64, String> {
    let deadline = Instant::now() + Duration::from_secs(45);
    let mut last = String::from("mono.dll not found");
    let mut last_log: Option<Instant> = None;
    loop {
        match find_mono_module(handle) {
            Ok(addr) => return Ok(addr),
            Err(err) => {
                last = err;
                let should_log = last_log.map(|t| t.elapsed() >= Duration::from_secs(3)).unwrap_or(true);
                if should_log {
                    let left = deadline.saturating_duration_since(Instant::now()).as_secs();
                    crate::log::info(&format!("waiting mono.dll ({last}) left={left}s"));
                    last_log = Some(Instant::now());
                }
                if Instant::now() >= deadline {
                    return Err(last);
                }
                thread::sleep(Duration::from_millis(800));
            }
        }
    }
}

fn find_mono_module(handle: HANDLE) -> Result<u64, String> {
    unsafe {
        let mut needed = 0u32;
        let _ = K32EnumProcessModulesEx(handle, null_mut(), 0, &mut needed, LIST_MODULES_ALL.0);
        if needed == 0 {
            return Err("EnumProcessModulesEx empty".into());
        }
        let count = (needed as usize) / size_of::<HMODULE>();
        let mut mods = vec![HMODULE::default(); count.max(1)];
        K32EnumProcessModulesEx(
            handle,
            mods.as_mut_ptr(),
            (mods.len() * size_of::<HMODULE>()) as u32,
            &mut needed,
            LIST_MODULES_ALL.0,
        )
        .ok()
        .map_err(|e| format!("EnumProcessModulesEx: {e}"))?;
        let mem = RemoteMemory::new(handle);
        for module in mods {
            if module.0 == 0 {
                continue;
            }
            let mut buf = [0u16; 260];
            let n = K32GetModuleFileNameExW(handle, module, &mut buf);
            if n == 0 {
                continue;
            }
            let path = String::from_utf16_lossy(&buf[..n as usize]).to_ascii_lowercase();
            if !path.contains("mono") {
                continue;
            }
            let mut info = MODULEINFO::default();
            if !K32GetModuleInformation(
                handle,
                module,
                &mut info,
                size_of::<MODULEINFO>() as u32,
            )
            .as_bool()
            {
                continue;
            }
            let base = info.lpBaseOfDll as u64;
            if export_has(&mem, base, "mono_get_root_domain").unwrap_or(false) {
                return Ok(base);
            }
        }
    }
    Err("mono.dll not found (is the game still loading?)".into())
}

fn resolve_exports(handle: HANDLE, mono: u64) -> Result<Exports, String> {
    let mem = RemoteMemory::new(handle);
    let all = list_exports(&mem, mono)?;
    let mut map = Vec::new();
    for name in MONO_EXPORTS {
        let addr = all
            .iter()
            .find(|(n, _)| n == name)
            .map(|(_, a)| *a)
            .ok_or_else(|| format!("missing mono export {name}"))?;
        map.push(((*name).to_string(), addr));
    }
    Ok(Exports { map })
}

fn export_has(mem: &RemoteMemory, base: u64, name: &str) -> Result<bool, String> {
    Ok(list_exports(mem, base)?.iter().any(|(n, _)| n == name))
}

fn list_exports(mem: &RemoteMemory, base: u64) -> Result<Vec<(String, u64)>, String> {
    let e_lfanew = mem.read_u32(base + 0x3C)? as u64;
    let nt = base + e_lfanew;
    let optional = nt + 0x18;
    let data_dir = optional + 0x70;
    let export_rva = mem.read_u32(data_dir)? as u64;
    if export_rva == 0 {
        return Ok(Vec::new());
    }
    let export = base + export_rva;
    let names = base + mem.read_u32(export + 0x20)? as u64;
    let ordinals = base + mem.read_u32(export + 0x24)? as u64;
    let functions = base + mem.read_u32(export + 0x1C)? as u64;
    let count = mem.read_u32(export + 0x18)? as usize;
    let mut out = Vec::with_capacity(count.min(512));
    for i in 0..count.min(2048) {
        let name_rva = mem.read_u32(names + (i as u64) * 4)? as u64;
        let name = mem.read_cstr(base + name_rva, 64)?;
        let ordinal = mem.read_u16(ordinals + (i as u64) * 2)? as u64;
        let func_rva = mem.read_u32(functions + ordinal * 4)? as u64;
        if func_rva != 0 {
            out.push((name, base + func_rva));
        }
    }
    Ok(out)
}

fn wchar_to_string(buf: &[u16]) -> String {
    let len = buf.iter().position(|&c| c == 0).unwrap_or(buf.len());
    String::from_utf16_lossy(&buf[..len])
}
