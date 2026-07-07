//! Shared DTOs and enums exposed across the flutter_rust_bridge boundary.
//!
//! These are the canonical types for the persisted reader model. They will
//! replace the throwaway JSON-snapshot types still living in `reader.rs`
//! (removed in P1a once the Flutter feed UI is rewired off the snapshot APIs).
//!
//! ## Naming note
//!
//! `Feed`, `ArticleViewMode`, and `FeedDraft` intentionally share their names
//! with legacy types in `reader.rs`. While `reader.rs` still exists they are
//! **not** marked `#[frb(unignore)]` to avoid duplicate Dart class generation.
//! P1a removes `reader.rs` and exposes them here.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// How a feed's articles should be displayed.
///
/// `External` is escaped to `external_` in generated Dart because `external`
/// is a Dart reserved word.
///
/// Note: `Default` is intentionally NOT implemented here to avoid a duplicate
/// key conflict with `reader::ArticleViewMode` during FRB codegen while both
/// modules coexist. P1a removes `reader.rs` and a `Default` impl can be added
/// back at that point.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum ArticleViewMode {
    Global,
    Webpage,
    Rendered,
    External,
}

// ---------------------------------------------------------------------------
// Feed-related DTOs
// ---------------------------------------------------------------------------

/// A subscribed feed.
///
/// Ported from Livo `src/shared/types/feed.ts` + the current `reader.rs` `Feed`,
/// using `DateTime<Utc>` for timestamps.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Feed {
    pub id: String,
    pub title: String,
    /// RSS/Atom source URL.
    pub source_url: String,
    /// Human-facing website URL (may differ from the feed URL).
    pub site_url: Option<String>,
    pub description: Option<String>,
    pub image_url: Option<String>,
    pub folder: Option<String>,
    pub category: Option<String>,
    pub article_view_mode: ArticleViewMode,
    pub unread_count: i32,
    pub article_count: i32,
    pub last_synced_at: Option<DateTime<Utc>>,
    pub last_error: Option<String>,
    pub error_count: i32,
    /// HTTP caching helpers.
    pub etag: Option<String>,
    pub last_modified: Option<String>,
    pub created_at: DateTime<Utc>,
}

/// A simple category/folder grouping.
#[flutter_rust_bridge::frb(unignore)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Category {
    pub id: String,
    pub title: String,
}

/// Input for subscribing to a new feed (pre-fetch).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeedDraft {
    pub title: String,
    pub source_url: String,
    pub site_url: Option<String>,
    pub description: Option<String>,
}

/// A feed URL discovered via auto-discovery (`<link rel="alternate">`), or the
/// input URL itself when it already serves a feed. Returned by
/// `api::feed::discover_feeds` so the Flutter add-feed dialog can let the user
/// pick among multiple candidates before subscribing.
#[flutter_rust_bridge::frb(unignore)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeedCandidate {
    /// Absolute feed URL.
    pub url: String,
    /// Optional human-readable title from the `<link title>` attribute.
    pub title: Option<String>,
    /// MIME type hint (`application/rss+xml`, `application/atom+xml`, ...).
    pub mime_type: Option<String>,
}

// ---------------------------------------------------------------------------
// Entry-related DTOs
// ---------------------------------------------------------------------------

/// A single article/entry belonging to a feed.
///
/// Ported from Livo `src/shared/types/entry.ts`, simplified to the fields
/// needed for the P0b persistence layer. Readability/AI/media fields will be
/// added in later tasks.
#[flutter_rust_bridge::frb(unignore)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Entry {
    pub id: String,
    pub feed_id: String,
    pub title: String,
    pub url: String,
    pub content: Option<String>,
    pub summary: Option<String>,
    pub author: Option<String>,
    pub image_url: Option<String>,
    pub published_at: DateTime<Utc>,
    pub is_read: bool,
    pub is_starred: bool,
    pub read_progress: Option<f64>,
    pub created_at: DateTime<Utc>,
}

/// Lightweight entry used in list views.
#[flutter_rust_bridge::frb(unignore)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EntryListItem {
    pub id: String,
    pub feed_id: String,
    pub feed_title: String,
    pub title: String,
    pub summary: String,
    pub published_at: Option<DateTime<Utc>>,
    pub is_read: bool,
    pub is_starred: bool,
}

/// Input for creating an entry (used during feed import).
#[flutter_rust_bridge::frb(unignore)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EntryDraft {
    pub title: String,
    pub url: String,
    pub author: Option<String>,
    pub summary: Option<String>,
    pub content: Option<String>,
    pub published_at: Option<DateTime<Utc>>,
}

// ---------------------------------------------------------------------------
// Sync / streaming
// ---------------------------------------------------------------------------

/// Progress payload pushed via `StreamSink` during a feed refresh.
///
/// Mirrors Livo's `FeedRefreshProgressPayload`
/// (`src/shared/renderer-events.ts`). One event is emitted per feed after it
/// has been fetched + upserted (success or failure), followed by a final
/// summary event with `done = true` and `feed_id = None`.
///
/// **FRB constraint**: a function with a `StreamSink<T>` parameter can only
/// return `()` or `Result<(), E>` — the return value is not delivered to Dart
/// as a value (only errors surface, as a stream/Future error). The cumulative
/// sync totals therefore ride on the final `SyncProgress` event (`done = true`)
/// rather than a separate `SyncReport` return value. `refresh_feed` (no stream)
/// does return a `SyncReport` directly.
#[flutter_rust_bridge::frb(unignore)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncProgress {
    /// Total feeds in this sync run.
    pub total: i32,
    /// Feeds processed so far (success + failure).
    pub completed: i32,
    /// Feeds that failed so far.
    pub failed: i32,
    /// The feed just processed (`None` on the final summary event).
    pub feed_id: Option<String>,
    /// Human-readable title of the feed just processed (`None` on the summary).
    pub feed_title: Option<String>,
    /// New entries inserted for THIS feed (0 on the summary event).
    pub new_entries: i32,
    /// Cumulative new entries across all feeds so far.
    pub total_new_entries: i32,
    /// `true` on the final summary event.
    pub done: bool,
    /// Per-feed error message when this feed failed (`None` on success/summary).
    pub error: Option<String>,
}

/// Final tally of a sync run. Returned directly by the non-streaming
/// `refresh_feed`; for the streaming `sync_feeds`/`refresh_all_feeds` the same
/// data is carried by the final `SyncProgress` event (see its docs for why).
#[flutter_rust_bridge::frb(unignore)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncReport {
    pub total: i32,
    pub completed: i32,
    pub failed: i32,
    pub new_entries: i32,
}
