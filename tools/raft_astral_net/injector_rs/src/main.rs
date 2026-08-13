#![cfg_attr(not(windows), allow(dead_code))]

mod log;
mod mono;

use std::collections::HashSet;
use std::env;
use std::path::PathBuf;
use std::thread;
use std::time::Duration;

fn usage() -> ! {
    eprintln!(
        "astral_mono_inject --dll <AstralRaftNet.dll> [--pid N | --process Raft | --watch Raft] \
         [--namespace AstralRaftNet] [--class Loader] [--method Init]"
    );
    std::process::exit(2);
}

struct Args {
    dll: PathBuf,
    pid: Option<u32>,
    process: Option<String>,
    watch: bool,
    namespace: String,
    class: String,
    method: String,
}

fn parse_args() -> Args {
    let mut dll = None;
    let mut pid = None;
    let mut process = None;
    let mut watch = false;
    let mut namespace = "AstralRaftNet".to_string();
    let mut class = "Loader".to_string();
    let mut method = "Init".to_string();
    let raw: Vec<String> = env::args().skip(1).collect();
    let mut i = 0;
    while i < raw.len() {
        match raw[i].as_str() {
            "--dll" | "-a" => {
                i += 1;
                dll = raw.get(i).cloned();
            }
            "--pid" | "-p" => {
                i += 1;
                pid = raw.get(i).and_then(|s| s.parse().ok());
            }
            "--process" => {
                i += 1;
                process = raw.get(i).cloned();
            }
            "--watch" => {
                watch = true;
                if let Some(next) = raw.get(i + 1) {
                    if !next.starts_with('-') {
                        i += 1;
                        process = Some(next.clone());
                    }
                }
            }
            "--namespace" => {
                i += 1;
                if let Some(v) = raw.get(i) {
                    namespace = v.clone();
                }
            }
            "--class" => {
                i += 1;
                if let Some(v) = raw.get(i) {
                    class = v.clone();
                }
            }
            "--method" => {
                i += 1;
                if let Some(v) = raw.get(i) {
                    method = v.clone();
                }
            }
            "-h" | "--help" => usage(),
            other => {
                eprintln!("unknown arg: {other}");
                usage();
            }
        }
        i += 1;
    }
    let Some(dll_raw) = dll else { usage() };
    let dll = PathBuf::from(dll_raw);
    Args {
        dll,
        pid,
        process,
        watch,
        namespace,
        class,
        method,
    }
}

fn main() {
    let args = parse_args();
    let dll_dir = args.dll.parent().unwrap_or_else(|| std::path::Path::new("."));
    log::init(&[dll_dir]);
    if !args.dll.is_file() {
        log::error(&format!("plugin not found: {}", args.dll.display()));
        std::process::exit(1);
    }
    log::info(&format!(
        "start dll={} pid={:?} process={:?} watch={} invoke={}.{}.{}",
        args.dll.display(),
        args.pid,
        args.process,
        args.watch,
        args.namespace,
        args.class,
        args.method
    ));
    let assembly = match std::fs::read(&args.dll) {
        Ok(bytes) => {
            log::info(&format!("read dll ok bytes={}", bytes.len()));
            bytes
        }
        Err(err) => {
            log::error(&format!("read dll failed: {err}"));
            std::process::exit(1);
        }
    };

    #[cfg(not(windows))]
    {
        let _ = (assembly, args);
        log::error("windows only");
        std::process::exit(1);
    }

    #[cfg(windows)]
    {
        if args.watch {
            let name = args
                .process
                .clone()
                .unwrap_or_else(|| "Raft".to_string());
            let mut seen: HashSet<u32> = HashSet::new();
            let mut idle_ticks = 0u32;
            log::info(&format!("watch process={name}"));
            loop {
                let pids = mono::pids_by_name(&name);
                if pids.is_empty() {
                    idle_ticks += 1;
                    if idle_ticks == 1 || idle_ticks % 15 == 0 {
                        log::info(&format!("watch: no process named {name}"));
                    }
                } else {
                    idle_ticks = 0;
                }
                seen.retain(|pid| pids.contains(pid));
                for pid in pids {
                    if !seen.insert(pid) {
                        continue;
                    }
                    log::info(&format!("watch: try pid={pid}"));
                    match mono::inject(
                        pid,
                        &assembly,
                        &args.namespace,
                        &args.class,
                        &args.method,
                    ) {
                        Ok(()) => log::info(&format!("injected pid={pid}")),
                        Err(err) => {
                            log::error(&format!("inject pid={pid} failed: {err}"));
                            seen.remove(&pid);
                        }
                    }
                }
                thread::sleep(Duration::from_secs(2));
            }
        }

        let pid = if let Some(pid) = args.pid {
            log::info(&format!("use --pid {pid}"));
            pid
        } else if let Some(name) = args.process.as_deref() {
            match mono::pids_by_name(name).first().copied() {
                Some(pid) => {
                    log::info(&format!("resolved process={name} pid={pid}"));
                    pid
                }
                None => {
                    log::error(&format!("process not found: {name}"));
                    std::process::exit(1);
                }
            }
        } else {
            usage();
        };

        match mono::inject(pid, &assembly, &args.namespace, &args.class, &args.method) {
            Ok(()) => {
                log::info(&format!("injected pid={pid}"));
            }
            Err(err) => {
                log::error(&err);
                std::process::exit(3);
            }
        }
    }
}
