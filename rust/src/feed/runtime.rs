//! Shared tokio runtime hosting async HTTP work (reqwest).
//!
//! FRB async functions are driven by FRB's own executor, which has no tokio
//! reactor. `reqwest` requires a tokio runtime to drive its I/O, so the API
//! layer spawns async work onto this shared multi-thread runtime and awaits
//! the returned `JoinHandle` (awaiting a `JoinHandle` does not itself require a
//! tokio context, so it composes cleanly with FRB's executor).

use std::sync::OnceLock;
use tokio::runtime::{Handle, Runtime};

static RUNTIME: OnceLock<Runtime> = OnceLock::new();

/// Returns a handle to the shared tokio runtime, initializing it on first use.
///
/// Two worker threads are enough for a client-side reader (HTTP fetches are
/// I/O-bound and rarely concurrent). `enable_all()` turns on the I/O driver
/// and timers that reqwest/hyper need.
pub(crate) fn handle() -> &'static Handle {
    RUNTIME
        .get_or_init(|| {
            tokio::runtime::Builder::new_multi_thread()
                .worker_threads(2)
                .enable_all()
                .build()
                .expect("failed to build tokio runtime")
        })
        .handle()
}
