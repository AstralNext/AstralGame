fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default() != "windows" {
        return;
    }
    println!("cargo:rerun-if-changed=app.manifest");
    let mut res = winres::WindowsResource::new();
    res.set_manifest_file("app.manifest");
    if let Err(err) = res.compile() {
        println!("cargo:warning=embed admin manifest failed: {err}");
    }
}
