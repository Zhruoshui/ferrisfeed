//! App-level FRB functions: initialization, version, and demo helpers.

use crate::api::error::AppError;
use crate::frb_generated::StreamSink;

/// Demo sync function (kept from the original `simple.rs` scaffold).
#[flutter_rust_bridge::frb(sync)]
pub fn greet(name: String) -> String {
    format!("Hello, {name}!")
}

/// Called once by `RustLib.init()` during app startup.
///
/// Sets up default user utilities only. The SQLite database is opened
/// separately by [`init_database`], which Dart invokes after `RustLib.init()`
/// with a platform-specific path (see `lib/main.dart`). `#[frb(init)]` cannot
/// take arguments, so the DB path is passed through a dedicated plain function
/// that runs on the FRB worker pool.
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// Opens the SQLite database at `path`, applies pragmas (WAL / foreign_keys /
/// synchronous), runs pending migrations, and stores the shared connection.
///
/// Plain `pub fn` (no `#[frb(sync)]`) so it runs on the FRB worker thread pool
/// and never blocks the Flutter UI isolate. Dart calls `await initDatabase(path)`
/// once after `RustLib.init()`.
#[flutter_rust_bridge::frb]
pub fn init_database(path: String) -> Result<(), AppError> {
    crate::db::connection::init_db(&path)
}

/// Returns the Rust crate version. Also serves as the codegen smoke-test that
/// ensures `AppError` is generated as a throwable Dart enum.
#[flutter_rust_bridge::frb(sync)]
pub fn app_version() -> Result<String, AppError> {
    Ok(env!("CARGO_PKG_VERSION").to_owned())
}

/// StreamSink smoke test (P1b). The first function in the crate to use FRB
/// streaming — verifies the `SseCodec` `StreamSink<T>` path end-to-end before
/// the feed-sync stream is built on top of it. Emits three `ping N` strings
/// then closes. Dart side receives a `Stream<String>`. Kept as a tiny
/// diagnostic helper; safe to remove once streaming is proven in production.
#[flutter_rust_bridge::frb]
pub fn ping_stream(sink: StreamSink<String>) {
    for i in 0..3 {
        let _ = sink.add(format!("ping {i}"));
    }
}
