//! Entry + Category CRUD exposed over flutter_rust_bridge, backed by SQLite.
//!
//! Uses the exposed `crate::api::types::{Entry, EntryDraft, EntryListItem,
//! AdjacentEntries, Category}` DTOs. All functions are plain `pub fn` (worker
//! pool) so the Flutter UI is never blocked by SQLite work.

use crate::api::error::AppError;
use crate::api::types::{AdjacentEntries, Category, Entry, EntryDraft, EntryListItem};
use crate::db::connection::with_db;
use crate::db::repositories;

/// Lists entries as lightweight list items, optionally filtered by feed,
/// unread, and/or starred state. Results are newest-first (`published_at DESC`)
/// and paginated by `limit`/`offset`.
#[flutter_rust_bridge::frb]
pub fn list_entries(
    feed_id: Option<String>,
    unread_only: bool,
    starred_only: bool,
    limit: u32,
    offset: u32,
) -> Result<Vec<EntryListItem>, AppError> {
    with_db(|conn| {
        repositories::entry::list_entries(
            conn,
            feed_id.as_deref(),
            unread_only,
            starred_only,
            limit as i64,
            offset as i64,
        )
    })
}

/// Returns a single entry by id, or `NotFound` if missing.
#[flutter_rust_bridge::frb]
pub fn get_entry(entry_id: String) -> Result<Entry, AppError> {
    with_db(|conn| repositories::entry::get_entry_by_id(conn, &entry_id))
}

/// Sets an entry's read state and recomputes the parent feed's cached
/// `unread_count`. `NotFound` if the entry does not exist.
#[flutter_rust_bridge::frb]
pub fn mark_entry_read(entry_id: String, is_read: bool) -> Result<(), AppError> {
    with_db(|conn| repositories::entry::mark_entry_read(conn, &entry_id, is_read))
}

/// Toggles an entry's starred flag and returns the new starred state.
/// `NotFound` if the entry does not exist.
#[flutter_rust_bridge::frb]
pub fn toggle_entry_star(entry_id: String) -> Result<bool, AppError> {
    with_db(|conn| repositories::entry::toggle_entry_star(conn, &entry_id))
}

/// Returns the previous (newer) and next (older) entry ids relative to
/// `entry_id`, within the same filter context used by the entry list. Used by
/// the reading UI for prev/next navigation.
#[flutter_rust_bridge::frb]
pub fn get_adjacent_entries(
    entry_id: String,
    feed_id: Option<String>,
    unread_only: bool,
    starred_only: bool,
) -> Result<AdjacentEntries, AppError> {
    with_db(|conn| {
        repositories::entry::get_adjacent_entries(
            conn,
            &entry_id,
            feed_id.as_deref(),
            unread_only,
            starred_only,
        )
    })
}

/// Inserts new entries for a feed, deduplicating by URL within the feed.
/// Returns the number of entries actually inserted.
#[flutter_rust_bridge::frb]
pub fn upsert_entries(feed_id: String, drafts: Vec<EntryDraft>) -> Result<i32, AppError> {
    with_db(|conn| repositories::entry::upsert_entries(conn, &feed_id, &drafts))
}

/// Searches entries by `LIKE %query%` on title + summary + content (parity
/// with Livo's `entry-repository.searchEntries`). Case-insensitive. Optional
/// `feed_id` scopes the search to one feed; `None` searches all feeds.
/// Results are newest-first and capped by `limit`. An empty/whitespace query
/// returns an empty list (no error).
#[flutter_rust_bridge::frb]
pub fn search_entries(
    query: String,
    feed_id: Option<String>,
    limit: u32,
) -> Result<Vec<EntryListItem>, AppError> {
    with_db(|conn| {
        repositories::entry::search_entries(conn, &query, feed_id.as_deref(), limit as i64)
    })
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
