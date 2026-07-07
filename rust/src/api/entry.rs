//! Entry + Category CRUD exposed over flutter_rust_bridge, backed by SQLite.
//!
//! Uses the already-exposed `crate::api::types::{Entry, EntryDraft,
//! EntryListItem, Category}` DTOs (no name clash with `reader.rs`). All
//! functions are plain `pub fn` (worker pool) so the Flutter UI is never
//! blocked by SQLite work.

use crate::api::error::AppError;
use crate::api::types::{Category, Entry, EntryDraft, EntryListItem};
use crate::db::connection::with_db;
use crate::db::repositories;

/// Lists entries as lightweight list items, optionally filtered by feed,
/// unread, and/or starred state. `limit` defaults to 50, `offset` to 0.
/// Results are newest-first.
#[flutter_rust_bridge::frb]
pub fn list_entries(
    feed_id: Option<String>,
    unread_only: bool,
    starred_only: bool,
    limit: Option<i32>,
    offset: Option<i32>,
) -> Result<Vec<EntryListItem>, AppError> {
    with_db(|conn| {
        repositories::entry::list_entries(
            conn,
            feed_id.as_deref(),
            unread_only,
            starred_only,
            limit.unwrap_or(50) as i64,
            offset.unwrap_or(0) as i64,
        )
    })
}

/// Returns a single entry by id, or `NotFound` if missing.
#[flutter_rust_bridge::frb]
pub fn get_entry(entry_id: String) -> Result<Entry, AppError> {
    with_db(|conn| repositories::entry::get_entry_by_id(conn, &entry_id))
}

/// Sets an entry's read state. `NotFound` if the entry does not exist.
#[flutter_rust_bridge::frb]
pub fn mark_entry_read(entry_id: String, is_read: bool) -> Result<(), AppError> {
    with_db(|conn| repositories::entry::mark_entry_read(conn, &entry_id, is_read))
}

/// Toggles an entry's starred flag. `NotFound` if the entry does not exist.
#[flutter_rust_bridge::frb]
pub fn toggle_entry_star(entry_id: String) -> Result<(), AppError> {
    with_db(|conn| repositories::entry::toggle_entry_star(conn, &entry_id))
}

/// Inserts new entries for a feed, deduplicating by URL within the feed.
/// Returns the number of entries actually inserted.
#[flutter_rust_bridge::frb]
pub fn upsert_entries(feed_id: String, drafts: Vec<EntryDraft>) -> Result<i32, AppError> {
    with_db(|conn| repositories::entry::upsert_entries(conn, &feed_id, &drafts))
}

/// Marks all entries as read, optionally scoped to one feed.
#[flutter_rust_bridge::frb]
pub fn mark_all_read(feed_id: Option<String>) -> Result<(), AppError> {
    with_db(|conn| repositories::entry::mark_all_read(conn, feed_id.as_deref()))
}

// --- Category CRUD ---------------------------------------------------------

#[flutter_rust_bridge::frb]
pub fn list_categories() -> Result<Vec<Category>, AppError> {
    with_db(|conn| repositories::category::list_categories(conn))
}

#[flutter_rust_bridge::frb]
pub fn upsert_category(category: Category) -> Result<(), AppError> {
    with_db(|conn| repositories::category::upsert_category(conn, &category))
}

#[flutter_rust_bridge::frb]
pub fn delete_category(category_id: String) -> Result<(), AppError> {
    with_db(|conn| repositories::category::delete_category(conn, &category_id))
}
