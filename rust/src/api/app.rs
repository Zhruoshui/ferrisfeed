//! App-level FRB functions: initialization, version, and demo helpers.

use crate::api::error::AppError;

/// Demo sync function (kept from the original `simple.rs` scaffold).
#[flutter_rust_bridge::frb(sync)]
pub fn greet(name: String) -> String {
    format!("Hello, {name}!")
}

/// Called once by `RustLib.init()` during app startup.
///
/// P0a: placeholder — sets up default user utilities only.
/// TODO(P0b): open the SQLite connection pool and run migrations here.
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// Returns the Rust crate version. Also serves as the codegen smoke-test that
/// ensures `AppError` is generated as a throwable Dart enum.
#[flutter_rust_bridge::frb(sync)]
pub fn app_version() -> Result<String, AppError> {
    Ok(env!("CARGO_PKG_VERSION").to_owned())
}
