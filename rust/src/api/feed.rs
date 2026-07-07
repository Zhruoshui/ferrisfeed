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
use crate::api::types::{FeedCandidate, SyncProgress, SyncReport};
use crate::db::connection::with_db;
use crate::db::repositories;
use crate::frb_generated::StreamSink;

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

// --- P1b: feed sync & refresh with progress streaming ----------------------
//
// These async fns await the sync orchestrator DIRECTLY (not via
// `feed::runtime::handle().spawn`). FRB v2.12's `DefaultHandler` already hosts
// a multi-threaded tokio runtime with an I/O driver + timer, so `reqwest`
// awaits work inside these `async fn`s without a second runtime (see
// `directory-structure.md` gotcha). The `StreamSink<SyncProgress>` parameter
// maps to a Dart `Stream<SyncProgress>`; because FRB stream-sink functions can
// only return `()` / `Result<(), E>`, the cumulative sync totals ride on the
// final `SyncProgress` event (`done = true`) rather than a `SyncReport` return.

/// Syncs the given feeds: fetch + parse + idempotent upsert + simhash near-dup
/// dedup per feed, emitting a `SyncProgress` event per feed plus a final
/// summary event. Per-feed failures are isolated (recorded on the feed row and
/// reported in the event's `error` field) and never abort the whole run.
#[flutter_rust_bridge::frb]
pub async fn sync_feeds(
    sink: StreamSink<SyncProgress>,
    feed_ids: Vec<String>,
) -> Result<(), AppError> {
    crate::feed::sync::sync_feeds_impl(sink, feed_ids).await
}

/// Syncs every subscribed feed. Convenience wrapper around [`sync_feeds`] that
/// loads all feed ids from the database first.
#[flutter_rust_bridge::frb]
pub async fn refresh_all_feeds(sink: StreamSink<SyncProgress>) -> Result<(), AppError> {
    let feed_ids = with_db(|conn| repositories::feed::list_feed_ids(conn))?;
    crate::feed::sync::sync_feeds_impl(sink, feed_ids).await
}

/// Refreshes a single feed (no progress stream). Returns the per-feed tally as
/// a `SyncReport`. Unlike the streaming variants, a network/parse failure here
/// surfaces as `Err` (there is only one feed, so isolation does not apply).
#[flutter_rust_bridge::frb]
pub async fn refresh_feed(feed_id: String) -> Result<SyncReport, AppError> {
    let new_entries = crate::feed::sync::refresh_feed_impl(feed_id).await?;
    Ok(SyncReport {
        total: 1,
        completed: 1,
        failed: 0,
        new_entries,
    })
}
