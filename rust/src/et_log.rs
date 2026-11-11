//! EasyTier 运行期日志落盘。
//!
//! EasyTier 不是子进程：本 crate 直接调用 `InstanceManager::run_network_instance`
//! 在进程内跑 ET，所以没有额外的 stdout/stderr 需要接管。问题在于 ET 的日志器
//! 只在它自己的 CLI 入口（`easytier::core`）里初始化，我们从未调用过
//! `common::log::init`，于是 ET 内部的 `tracing` / `log` 事件全部被丢弃，Dart 侧
//! 只能看到我们手工映射的 GlobalCtxEvent 摘要。
//!
//! 这里在 FRB 初始化阶段（早于任何实例创建）补上全局日志器：ET 与本 crate 的
//! tracing 事件统一写入 `log.txt`，由 ET 自带的 rolling appender 负责追加写入、
//! 按体积切分并限制保留份数。

use std::path::{Path, PathBuf};
use std::sync::Once;
use std::time::Duration;

use easytier::common::config::{FileLoggerConfig, LoggingConfig};

/// 单文件上限 10MB、保留 5 份，总量上限约 50MB，长期运行也不会把磁盘写满。
const MAX_FILE_SIZE_MB: u64 = 10;
const MAX_FILE_COUNT: usize = 5;
const FILE_NAME: &str = "log.txt";
/// 默认 info：ET 的连接建立/断开、网卡就绪、DHCP 变更等关键事件都在 info。
/// 更细的握手与路由细节在 debug，可用环境变量提高，无需改代码或重新编译。
const DEFAULT_LEVEL: &str = "info";
/// 日志级别出口：取值 off/error/warn/info/debug/trace。
const LEVEL_ENV: &str = "ASTRAL_ET_LOG_LEVEL";
/// 落盘目录出口：便于排查时把日志固定到指定位置。
const DIR_ENV: &str = "ASTRAL_ET_LOG_DIR";

static INIT: Once = Once::new();

/// 安装全局日志器（幂等）。调用方需保证早于任何 EasyTier 实例创建。
pub(crate) fn init() {
    INIT.call_once(init_inner);
}

fn init_inner() {
    let level = resolve_level();
    let Some(dir) = resolve_dir() else {
        eprintln!("[et_log] 没有可写目录，EasyTier 日志保持关闭");
        return;
    };

    let config = LoggingConfig {
        file_logger: Some(FileLoggerConfig {
            level: Some(level.clone()),
            file: Some(FILE_NAME.to_owned()),
            dir: Some(dir.to_string_lossy().into_owned()),
            size_mb: Some(MAX_FILE_SIZE_MB),
            count: Some(MAX_FILE_COUNT),
        }),
        console_logger: None,
    };

    if let Err(error) = easytier::common::log::init(&config, false) {
        eprintln!("[et_log] 安装 EasyTier 日志器失败: {error}");
        return;
    }

    // ET 的文件 sink 是 BufWriter：要么攒满 8KB，要么切分文件时才落盘。
    // 低频运行时用户打开 log.txt 会看到空文件，所以补一个定时 flush，
    // 保持"追加 + 缓冲"的同时做到秒级可见。
    std::thread::spawn(|| loop {
        std::thread::sleep(Duration::from_secs(1));
        log::logger().flush();
    });

    tracing::info!(
        target: "ASTRAL",
        path = %dir.join(FILE_NAME).display(),
        level = %level,
        version = easytier::VERSION,
        "EasyTier 日志落盘已启动"
    );
}

fn resolve_level() -> String {
    let Ok(raw) = std::env::var(LEVEL_ENV) else {
        return DEFAULT_LEVEL.to_owned();
    };
    let level = raw.trim().to_ascii_lowercase();
    if matches!(
        level.as_str(),
        "off" | "error" | "warn" | "info" | "debug" | "trace"
    ) {
        level
    } else {
        eprintln!("[et_log] 忽略无效的 {LEVEL_ENV}={raw:?}");
        DEFAULT_LEVEL.to_owned()
    }
}

fn resolve_dir() -> Option<PathBuf> {
    if let Some(custom) = std::env::var_os(DIR_ENV).map(PathBuf::from) {
        if is_writable_dir(&custom) {
            return Some(custom);
        }
        eprintln!("[et_log] {DIR_ENV} 指向的目录不可写: {}", custom.display());
    }
    candidate_dirs().into_iter().find(|dir| is_writable_dir(dir))
}

/// 优先 exe 旁的 `logs`（便携版/开发版可直接找到），安装到 Program Files 时
/// 普通用户没有写权限，退回 `%LOCALAPPDATA%\Astral Game\logs`。
fn candidate_dirs() -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    if let Some(parent) = std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(Path::to_path_buf))
    {
        dirs.push(parent.join("logs"));
    }
    if let Some(local) = std::env::var_os("LOCALAPPDATA") {
        dirs.push(PathBuf::from(local).join("Astral Game").join("logs"));
    }
    // 移动端起进程 exe 位于只读分区，最后用临时目录兜底，至少不静默丢日志。
    dirs.push(std::env::temp_dir().join("astral-game-logs"));
    dirs
}

fn is_writable_dir(dir: &Path) -> bool {
    if std::fs::create_dir_all(dir).is_err() {
        return false;
    }
    let probe = dir.join(".astral-write-test");
    std::fs::write(&probe, b"1")
        .and_then(|_| std::fs::remove_file(&probe))
        .is_ok()
}
