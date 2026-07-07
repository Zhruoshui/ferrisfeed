//! Feed fetching, parsing, discovery, and normalization.
//!
//! This module is NOT exposed to flutter_rust_bridge (only `crate::api` is).
//! It owns the `reqwest` HTTP client, the `feed-rs` parser, the `scraper`
//! discovery helper, and the shared tokio runtime. The API layer in
//! `api/feed.rs` spawns async work onto the runtime (see `runtime::handle`)
//! and delegates here.
//!
//! Layering: `api/feed.rs` -> `feed::{discover_feeds_impl, subscribe_feed_impl}`
//! -> `feed::{fetch,parse,discover,normalize}` + `db::repositories::feed`.
//! Third-party types (`reqwest`, `feed-rs`, `scraper`) never cross the FRB
//! boundary.

pub(crate) mod discover;
pub(crate) mod fetch;
pub(crate) mod normalize;
pub(crate) mod parse;
pub(crate) mod runtime;
pub(crate) mod simhash;
pub(crate) mod sync;

use chrono::Utc;
use uuid::Uuid;

use crate::api::reader::{ArticleViewMode, Feed};
use crate::api::types::FeedCandidate;
use crate::api::AppError;
use crate::db::connection::with_db;
use crate::db::repositories;

/// Fetches `url` and returns feed candidates.
///
/// - If the URL already serves a feed (by content-type, or by successful parse
///   when the server omits a feed content-type), it is returned as a single
///   candidate.
/// - Otherwise the response is treated as HTML and scanned for
///   `<link rel="alternate">` feed links via `scraper`.
pub(crate) async fn discover_feeds_impl(url: &str) -> Result<Vec<FeedCandidate>, AppError> {
    let (bytes, content_type) = fetch::fetch_url(url).await?;

    if is_feed_content_type(&content_type) {
        return Ok(vec![FeedCandidate {
            url: url.to_string(),
            title: None,
            mime_type: Some(content_type),
        }]);
    }

    // Some servers omit a feed content-type; try parsing directly before
    // assuming HTML. feed-rs is strict enough that HTML won't parse as a feed.
    if parse::parse_feed(&bytes, url).is_ok() {
        return Ok(vec![FeedCandidate {
            url: url.to_string(),
            title: None,
            mime_type: None,
        }]);
    }

    let html = String::from_utf8_lossy(&bytes);
    Ok(discover::discover_feed_links(&html, url))
}

/// Fetches, parses, normalizes, and persists a feed (metadata only — entry
/// sync is P1b). Returns the persisted `Feed`.
///
/// Idempotent: if a feed with the same `source_url` already exists, the
/// existing record is returned instead of creating a duplicate (the
/// `feeds_source_url_idx` unique index would otherwise reject the insert).
pub(crate) async fn subscribe_feed_impl(url: &str) -> Result<Feed, AppError> {
    let (bytes, _content_type) = fetch::fetch_url(url).await?;
    let parsed = parse::parse_feed(&bytes, url)?;

    let title = normalize::normalize_feed_title(&parsed.title, parsed.site_url.as_deref(), url);
    let site_url = normalize::normalize_site_url(parsed.site_url.as_deref(), url);

    let feed = Feed {
        id: Uuid::new_v4().to_string(),
        title,
        source_url: url.to_string(),
        site_url: site_url.unwrap_or_default(),
        description: parsed.description.unwrap_or_default(),
        unread_count: 0,
        article_count: 0,
        last_synced_at: Some(Utc::now().to_rfc3339()),
        article_view_mode: ArticleViewMode::default(),
        last_error: None,
        error_count: 0,
    };

    // The DB touch is sync and short (a single lookup + upsert), so it runs
    // directly on the tokio worker thread. The mutex guard is never held across
    // an `.await` (with_db locks and releases synchronously).
    with_db(|conn| {
        if let Some(existing) =
            repositories::feed::get_feed_by_source_url(conn, &feed.source_url)?
        {
            return Ok(existing);
        }
        repositories::feed::upsert_feed(conn, &feed)?;
        Ok(feed)
    })
}

fn is_feed_content_type(content_type: &str) -> bool {
    let lower = content_type.to_lowercase();
    lower.contains("rss") || lower.contains("atom") || lower.contains("feed+json")
}
