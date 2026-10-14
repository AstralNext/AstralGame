#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
    // Ensure the shared P2P Tokio runtime is ready on first FRB init.
    crate::api::p2p::ensure_runtime();
}
