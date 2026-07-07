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
/// (`src/shared/renderer-events.ts`).
#[flutter_rust_bridge::frb(unignore)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncProgress {
    pub total: i32,
    pub completed: i32,
    pub feed_id: Option<String>,
    pub new_entries: i32,
    pub done: bool,
}
