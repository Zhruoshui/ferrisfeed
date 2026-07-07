//! SQLite connection management.
//!
//! Mirrors Livo's `doc/Livo/src/main/database/sqlite-adapter.ts`: a single
//! connection opened once at startup with `journal_mode=WAL`,
//! `foreign_keys=ON`, and `synchronous=NORMAL`, then shared across
//! repositories.
//!
//! Because `rusqlite::Connection` is `Send` but `!Sync`, the connection lives
//! behind a `parking_lot::Mutex` inside a `OnceLock`. API functions borrow it
//! via [`with_db`], which locks for the duration of a single short query and
//! releases immediately — never across an `.await` point.

use parking_lot::Mutex;
use rusqlite::Connection;
use std::sync::OnceLock;

use crate::api::AppError;
use crate::db::migrations;

static DB: OnceLock<Mutex<Connection>> = OnceLock::new();

// --- Error bridge: rusqlite / io / serde_json -> AppError -------------------
// Defined here (not in `api/error.rs`) so the `api/` module never references
// rusqlite types, which keeps flutter_rust_bridge codegen away from them.

impl From<rusqlite::Error> for AppError {
    fn from(e: rusqlite::Error) -> Self {
        Self::Database(e.to_string())
    }
}

impl From<std::io::Error> for AppError {
    fn from(e: std::io::Error) -> Self {
        Self::Io(e.to_string())
    }
}

impl From<serde_json::Error> for AppError {
    fn from(e: serde_json::Error) -> Self {
        Self::Database(format!("json decode error: {e}"))
    }
}

/// Opens the database at `path`, applies the WAL/FK/synchronous pragmas, runs
/// pending migrations, and stores the connection in the global slot. Called
/// once from `api::app::init_database` during app startup.
///
/// Returns an error if the database has already been initialized.
pub fn init_db(path: &str) -> Result<(), AppError> {
    let mut conn = Connection::open(path)?;
    conn.pragma_update(None, "journal_mode", "WAL")?;
    conn.pragma_update(None, "foreign_keys", "ON")?;
    conn.pragma_update(None, "synchronous", "NORMAL")?;
    migrations::run(&mut conn)?;
    DB.set(Mutex::new(conn))
        .map_err(|_| AppError::database("database already initialized"))?;
    Ok(())
}

/// Borrows the shared connection and runs `f` against it. The lock is held only
/// for the duration of `f` (short blocking DB work that runs on the FRB worker
/// pool, never on the Flutter UI isolate).
pub fn with_db<F, R>(f: F) -> Result<R, AppError>
where
    F: FnOnce(&Connection) -> Result<R, AppError>,
{
    let mutex = DB
        .get()
        .ok_or_else(|| AppError::database("database not initialized"))?;
    let guard = mutex.lock();
    f(&*guard)
}
