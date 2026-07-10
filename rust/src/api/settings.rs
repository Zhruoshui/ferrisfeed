//! Settings CRUD exposed over flutter_rust_bridge.
//!
//! Wraps the `settings(key TEXT PK, value TEXT)` table (migration v3). The
//! table is a generic key/value store; typed helpers here give Flutter a
//! stable, discoverable API for the values it needs to configure today
//! (currently: the RSSHub base URL used by the special-feed provider).
//!
//! Plain `pub fn` (no `#[frb(sync)]`, no `async`): a single indexed DB touch
//! runs on the FRB worker pool and returns a `Future` to Dart, so the Flutter
//! UI is never blocked. See `directory-structure.md` sync/async policy.

use crate::api::error::AppError;
use crate::db::connection::with_db;
use crate::db::repositories::settings as settings_repo;
use crate::feed::providers::rsshub::{DEFAULT_RSSHUB_BASE_URL, RSSHUB_BASE_URL_KEY};

/// Returns the raw value stored under `key`, or `None` if unset.
///
/// Prefer the typed getters (e.g. [`get_rsshub_base_url`]) when they exist —
/// they apply defaults and value normalization. This raw variant exists for
/// keys that don't have a typed accessor yet (P4/P6 config knobs).
#[flutter_rust_bridge::frb]
pub fn get_setting(key: String) -> Result<Option<String>, AppError> {
    with_db(|conn| settings_repo::get_setting(conn, &key))
}

/// Inserts or updates the value for `key`. Passing `None` stores SQL `NULL`
/// (an "explicitly cleared" setting); passing `Some("")` is treated the same
/// by the typed getters, which fall back to their default.
#[flutter_rust_bridge::frb]
pub fn set_setting(key: String, value: Option<String>) -> Result<(), AppError> {
    with_db(|conn| settings_repo::set_setting(conn, &key, value.as_deref()))
}

/// Returns the configured RSSHub base URL, or the built-in default
/// (`https://rsshub.app`) when nothing is stored. The returned URL has no
/// trailing slash (matching what the RSSHub provider consumes when building
/// per-subscription URLs).
///
/// This mirrors Livo's `settings.general.rsshubInstance ||
/// DEFAULT_RSSHUB_INSTANCE` fallback in `feed-source-provider.ts`.
#[flutter_rust_bridge::frb]
pub fn get_rsshub_base_url() -> Result<String, AppError> {
    with_db(|conn| crate::feed::providers::rsshub::resolve_base_url(conn))
}

/// Persists the RSSHub base URL. Passing `None` or an all-whitespace/empty
/// string clears the override; subsequent reads fall back to the default.
///
/// The stored value is trimmed but otherwise unvalidated — callers already
/// know the URL is well-formed (the settings dialog validates), and the fetch
/// layer produces a clear network error at subscribe time otherwise.
#[flutter_rust_bridge::frb]
pub fn set_rsshub_base_url(url: Option<String>) -> Result<(), AppError> {
    let trimmed = url.map(|s| s.trim().to_string()).filter(|s| !s.is_empty());
    with_db(|conn| settings_repo::set_setting(conn, RSSHUB_BASE_URL_KEY, trimmed.as_deref()))
}

/// The compile-time default RSSHub base URL. Exposed so the Flutter settings
/// dialog can render it as a placeholder / reset target without hard-coding
/// the same string on both sides of the bridge.
#[flutter_rust_bridge::frb]
pub fn default_rsshub_base_url() -> String {
    DEFAULT_RSSHUB_BASE_URL.to_string()
}
