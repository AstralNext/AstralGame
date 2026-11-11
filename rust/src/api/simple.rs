#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
    // 日志器必须在任何 EasyTier 实例创建前安装，否则启动阶段的日志会被丢弃。
    crate::et_log::init();
    // Ensure the shared P2P Tokio runtime is ready on first FRB init.
    crate::api::p2p::ensure_runtime();
}
