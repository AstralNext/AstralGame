#![cfg_attr(not(windows), allow(dead_code))]

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
    if !args.dll.is_file() {
        eprintln!("plugin not found: {}", args.dll.display());
        std::process::exit(1);
    }
    let assembly = std::fs::read(&args.dll).expect("read dll");

    #[cfg(not(windows))]
    {
        let _ = (assembly, args);
        eprintln!("windows only");
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
            println!("watch process={name} dll={}", args.dll.display());
            loop {
                let pids = mono::pids_by_name(&name);
                seen.retain(|pid| pids.contains(pid));
                for pid in pids {
                    if !seen.insert(pid) {
                        continue;
                    }
                    match mono::inject(
                        pid,
                        &assembly,
                        &args.namespace,
                        &args.class,
                        &args.method,
                    ) {
                        Ok(()) => println!("injected pid={pid}"),
                        Err(err) => {
                            eprintln!("inject pid={pid} failed: {err}");
                            seen.remove(&pid);
                        }
                    }
                }
                thread::sleep(Duration::from_secs(2));
            }
        }

        let pid = if let Some(pid) = args.pid {
            pid
        } else if let Some(name) = args.process.as_deref() {
            *mono::pids_by_name(name).first().unwrap_or_else(|| {
                eprintln!("process not found: {name}");
                std::process::exit(1);
            })
        } else {
            usage();
        };

        match mono::inject(pid, &assembly, &args.namespace, &args.class, &args.method) {
            Ok(()) => {
                println!("injected pid={pid}");
            }
            Err(err) => {
                eprintln!("{err}");
                std::process::exit(3);
            }
        }
    }
}
