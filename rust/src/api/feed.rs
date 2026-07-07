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
use crate::api::types::FeedCandidate;
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

/// Updates a feed's editable metadata (title, site_url, description).
/// `NotFound` if the feed does not exist.
#[flutter_rust_bridge::frb]
pub fn update_feed(
    feed_id: String,
    title: String,
    site_url: String,
    description: String,
) -> Result<Feed, AppError> {
    with_db(|conn| {
        let mut feed = repositories::feed::get_feed_by_id(conn, &feed_id)?
            .ok_or_else(|| AppError::not_found("feed", &feed_id))?;
        feed.title = title;
        feed.site_url = site_url;
        feed.description = description;
        repositories::feed::upsert_feed(conn, &feed)?;
        Ok(feed)
    })
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

// --- Network-backed subscription (P1a) -------------------------------------
//
// These are `async fn` (never `#[frb(sync)]`): the body runs on a tokio runtime
// spawned via `feed::runtime::handle()` so network I/O never blocks the FRB
// worker pool or the Flutter UI isolate. `feed-rs`/`reqwest`/`scraper` types
// stay internal to the `feed/` module — only `Feed`/`FeedCandidate`/`AppError`
// cross the FRB boundary.

/// Discovers feed URLs at a page. If `url` already serves a feed, returns it
/// as a single candidate; otherwise scans the HTML for
/// `<link rel="alternate" type="application/rss+xml|atom+xml">`.
#[flutter_rust_bridge::frb]
pub async fn discover_feeds(url: String) -> Result<Vec<FeedCandidate>, AppError> {
    crate::feed::runtime::handle()
        .spawn(async move { crate::feed::discover_feeds_impl(&url).await })
        .await
        .map_err(|e| AppError::Io(e.to_string()))?
}

/// Subscribes to a feed by URL: fetch + parse + normalize + persist (metadata
/// only — entry sync is P1b). Returns the persisted `Feed`. Idempotent: an
/// existing subscription with the same source URL returns its record.
#[flutter_rust_bridge::frb]
pub async fn subscribe_feed(url: String) -> Result<Feed, AppError> {
    crate::feed::runtime::handle()
        .spawn(async move { crate::feed::subscribe_feed_impl(&url).await })
        .await
        .map_err(|e| AppError::Io(e.to_string()))?
}
