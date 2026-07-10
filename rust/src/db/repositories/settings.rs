//! Settings repository: CRUD for the generic `settings(key TEXT PK, value TEXT)`
//! table introduced by migration v3.
//!
//! The table is a key/value store for user-facing configuration that must
//! survive process restarts. First consumer is the RSSHub bridge (the special-
//! feed provider reads `rsshub.base_url` here); later phases (AI provider
//! config in P4, settings UI in P6) reuse the same table.
//!
//! Mirrors Livo's `settingsProvider` (`electron-store`) at a lower level - we
//! don't validate against a schema here; that's the caller's job (see e.g.
//! `api::settings::rsshub_base_url`, which supplies a sensible default when
//! nothing is stored).
//!
//! Ports Livo `doc/Livo/src/shared/settings-schema.ts`: the same idea, but
//! Rust-persisted and untyped (a `TEXT` value column). Typed accessors sit on
//! top in the `api::settings` module.

use rusqlite::{params, Connection};

use crate::api::AppError;

/// Returns the value for `key`, or `None` if unset.
pub fn get_setting(conn: &Connection, key: &str) -> Result<Option<String>, AppError> {
    let mut stmt = conn.prepare("SELECT value FROM settings WHERE key = ?1")?;
    let mut rows = stmt.query_map(params![key], |row| row.get::<_, Option<String>>(0))?;
    match rows.next() {
        Some(row) => Ok(row?),
        None => Ok(None),
    }
}

/// Inserts or updates the value for `key`. A `None` value stores SQL `NULL`
/// (equivalent to "explicitly cleared"); callers who mean "delete the row"
/// should use [`delete_setting`] instead.
pub fn set_setting(conn: &Connection, key: &str, value: Option<&str>) -> Result<(), AppError> {
    conn.execute(
        "INSERT INTO settings (key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        params![key, value],
    )?;
    Ok(())
}

/// Removes a setting row entirely. No-op if the key is not present.
#[allow(dead_code)]
pub fn delete_setting(conn: &Connection, key: &str) -> Result<(), AppError> {
    conn.execute("DELETE FROM settings WHERE key = ?1", params![key])?;
    Ok(())
}
