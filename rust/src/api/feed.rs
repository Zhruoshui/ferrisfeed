//! Feed CRUD exposed over flutter_rust_bridge, backed by SQLite.
//!
//! Reuses the already-exposed `crate::api::reader::{Feed, ArticleViewMode}`
//! types as the boundary DTOs. While `reader.rs` (the JSON-snapshot prototype)
//! still exists, exposing `types::Feed` would generate a duplicate Dart `Feed`
//! class (both modules are imported by `frb_generated.dart`), so the persisted
//! feed API shares `reader::Feed`. P1a removes `reader.rs` and switches this to
//! `types::Feed`.
//!
//! All functions are plain `pub fn` (no `#[frb(sync)]`): they run on the FRB
//! worker thread pool and return a `Future` to Dart, so the Flutter UI is never
//! blocked by SQLite work (see `directory-structure.md` sync/async policy).

use crate::api::error::AppError;
use crate::api::reader::{ArticleViewMode, Feed};
use crate::db::connection::with_db;
use crate::db::repositories;

/// Returns every feed, ordered by title.
#[flutter_rust_bridge::frb]
pub fn list_feeds() -> Result<Vec<Feed>, AppError> {
    with_db(|conn| repositories::feed::list_feeds(conn))
}

/// Returns a single feed by id, or `NotFound` if missing.
#[flutter_rust_bridge::frb]
pub fn get_feed(feed_id: String) -> Result<Feed, AppError> {
    with_db(|conn| {
        repositories::feed::get_feed_by_id(conn, &feed_id)?
            .ok_or_else(|| AppError::not_found("feed", &feed_id))
    })
}

/// Inserts or updates a feed by id.
#[flutter_rust_bridge::frb]
pub fn upsert_feed(feed: Feed) -> Result<(), AppError> {
    with_db(|conn| repositories::feed::upsert_feed(conn, &feed))
}

/// Deletes a feed (and, via FK cascade, its entries). `NotFound` if missing.
#[flutter_rust_bridge::frb]
pub fn delete_feed(feed_id: String) -> Result<(), AppError> {
    with_db(|conn| {
        if repositories::feed::get_feed_by_id(conn, &feed_id)?.is_none() {
            return Err(AppError::not_found("feed", &feed_id));
        }
        repositories::feed::delete_feed(conn, &feed_id)
    })
}

/// Sets a feed's article view mode.
#[flutter_rust_bridge::frb]
pub fn set_feed_view_mode(feed_id: String, view_mode: ArticleViewMode) -> Result<(), AppError> {
    with_db(|conn| repositories::feed::set_feed_view_mode(conn, &feed_id, view_mode))
}
