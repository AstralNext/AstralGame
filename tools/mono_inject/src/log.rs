use std::fs::OpenOptions;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::sync::OnceLock;
use std::time::{SystemTime, UNIX_EPOCH};

static LOG_PATHS: OnceLock<Vec<PathBuf>> = OnceLock::new();

pub fn init(extra_dirs: &[&Path]) {
    let mut paths = Vec::new();
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            push_unique(&mut paths, dir.join("astral_mono_inject.log"));
        }
    }
    for dir in extra_dirs {
        push_unique(&mut paths, dir.join("astral_mono_inject.log"));
    }
    if let Ok(tmp) = std::env::var("TEMP").or_else(|_| std::env::var("TMP")) {
        push_unique(&mut paths, PathBuf::from(tmp).join("astral_mono_inject.log"));
    }
    let _ = LOG_PATHS.set(paths.clone());
    let listed = paths
        .iter()
        .map(|p| p.display().to_string())
        .collect::<Vec<_>>()
        .join(" | ");
    info(&format!("log -> {listed}"));
}

pub fn info(msg: &str) {
    write_line("INFO", msg);
}

#[allow(dead_code)]
pub fn warn(msg: &str) {
    write_line("WARN", msg);
}

pub fn error(msg: &str) {
    write_line("ERROR", msg);
}

fn push_unique(paths: &mut Vec<PathBuf>, path: PathBuf) {
    if !paths.iter().any(|p| p == &path) {
        paths.push(path);
    }
}

fn write_line(level: &str, msg: &str) {
    let line = format!("{} [{level}] {msg}", timestamp());
    let _ = writeln!(io::stdout(), "{line}");
    let _ = io::stdout().flush();
    let _ = writeln!(io::stderr(), "{line}");
    let _ = io::stderr().flush();
    if let Some(paths) = LOG_PATHS.get() {
        for path in paths {
            if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path) {
                let _ = writeln!(file, "{line}");
                let _ = file.flush();
            }
        }
    }
}

fn timestamp() -> String {
    let d = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    let secs = d.as_secs();
    let millis = d.subsec_millis();
    let (h, rem) = ((secs / 3600) % 24, secs % 3600);
    let (m, s) = (rem / 60, rem % 60);
    format!("{h:02}:{m:02}:{s:02}.{millis:03}")
}
