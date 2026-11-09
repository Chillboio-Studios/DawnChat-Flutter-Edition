#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
    // Both reqwest and tungstenite pull rustls; pick one provider explicitly.
    let _ = rustls::crypto::ring::default_provider().install_default();
}
