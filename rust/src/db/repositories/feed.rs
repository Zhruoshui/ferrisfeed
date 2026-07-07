//! Feed repository: CRUD for the `feeds` table.
//!
//! Uses the already-FRB-exposed `crate::api::reader::{Feed, ArticleViewMode}`
//! types as the boundary DTO. While `reader.rs` (the JSON-snapshot prototype)
//! still exists, `types::Feed` cannot be exposed without producing a duplicate
//! Dart `Feed` class, so the persisted feed API reuses `reader::Feed`. P1a
//! removes `reader.rs` and switches this to `types::Feed`.
//!
//! Dates are stored as epoch-millis `INTEGER`; `reader::Feed` carries
//! `last_synced_at` as an RFC3339 `String`, so the repo converts at the
//! boundary. `article_view_mode` is stored as lowercase `TEXT`.

use chrono::{DateTime, Utc};
use rusqlite::{params, Connection, Row};

use crate::api::reader::{ArticleViewMode, Feed};
use crate::api::AppError;

/// Inserts or updates a feed by `id`. `created_at` is set on insert and
/// preserved on update (the `ON CONFLICT` clause does not touch it).
pub fn upsert_feed(conn: &Connection, feed: &Feed) -> Result<(), AppError> {
    let last_synced_ms = feed.last_synced_at.as_deref().and_then(parse_iso_to_ms);
    conn.execute(
        "INSERT INTO feeds
            (id, title, source_url, site_url, description, unread_count,
             article_count, last_synced_at, article_view_mode, last_error,
             error_count, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)
         ON CONFLICT(id) DO UPDATE SET
             title = excluded.title,
             source_url = excluded.source_url,
             site_url = excluded.site_url,
             description = excluded.description,
             unread_count = excluded.unread_count,
             article_count = excluded.article_count,
             last_synced_at = excluded.last_synced_at,
             article_view_mode = excluded.article_view_mode,
             last_error = excluded.last_error,
             error_count = excluded.error_count",
        params![
            feed.id,
            feed.title,
            feed.source_url,
            feed.site_url,
            feed.description,
            feed.unread_count,
            feed.article_count,
            last_synced_ms,
            view_mode_str(&feed.article_view_mode),
            feed.last_error,
            feed.error_count,
            Utc::now().timestamp_millis(),
        ],
    )?;
    Ok(())
}

pub fn get_feed_by_id(conn: &Connection, id: &str) -> Result<Option<Feed>, AppError> {
    let mut stmt = conn.prepare("SELECT * FROM feeds WHERE id = ?1")?;
    let mut rows = stmt.query_map(params![id], feed_from_row)?;
    match rows.next() {
        Some(row) => Ok(Some(row?)),
        None => Ok(None),
    }
}

pub fn get_feed_by_source_url(conn: &Connection, url: &str) -> Result<Option<Feed>, AppError> {
    let mut stmt = conn.prepare("SELECT * FROM feeds WHERE source_url = ?1")?;
    let mut rows = stmt.query_map(params![url], feed_from_row)?;
    match rows.next() {
        Some(row) => Ok(Some(row?)),
        None => Ok(None),
    }
}

pub fn list_feeds(conn: &Connection) -> Result<Vec<Feed>, AppError> {
    let mut stmt = conn.prepare("SELECT * FROM feeds ORDER BY title COLLATE NOCASE")?;
    let rows = stmt.query_map([], feed_from_row)?;
    Ok(rows.collect::<Result<Vec<_>, _>>()?)
}

/// Returns just the feed ids, ordered by title. Used by `refresh_all_feeds`
/// to drive a sync over every subscribed feed without loading full rows.
pub fn list_feed_ids(conn: &Connection) -> Result<Vec<String>, AppError> {
    let mut stmt = conn.prepare("SELECT id FROM feeds ORDER BY title COLLATE NOCASE")?;
    let rows = stmt.query_map([], |row| row.get::<_, String>(0))?;
    Ok(rows.collect::<Result<Vec<_>, _>>()?)
}

pub fn delete_feed(conn: &Connection, id: &str) -> Result<(), AppError> {
    // FK ON DELETE CASCADE removes the feed's entries.
    conn.execute("DELETE FROM feeds WHERE id = ?1", params![id])?;
    Ok(())
}

pub fn set_feed_view_mode(
    conn: &Connection,
    id: &str,
    mode: ArticleViewMode,
) -> Result<(), AppError> {
    conn.execute(
        "UPDATE feeds SET article_view_mode = ?1 WHERE id = ?2",
        params![view_mode_str(&mode), id],
    )?;
    Ok(())
}

/// Recomputes the cached `article_count` / `unread_count` for a feed from its
/// entries. Called after entry mutations to keep the denormalized counts
/// consistent (mirrors Livo's `recalculate_feed_counts`).
pub fn recompute_feed_counts(conn: &Connection, feed_id: &str) -> Result<(), AppError> {
    conn.execute(
        "UPDATE feeds SET
             article_count = (SELECT COUNT(*) FROM entries WHERE feed_id = ?1),
             unread_count = (SELECT COUNT(*) FROM entries WHERE feed_id = ?1 AND is_read = 0)
         WHERE id = ?1",
        params![feed_id],
    )?;
    Ok(())
}

/// Records a successful sync: stamps `last_synced_at`, clears `last_error`,
/// and resets `error_count` (mirrors Livo clearing the error state on success).
pub fn record_sync_success(conn: &Connection, feed_id: &str) -> Result<(), AppError> {
    conn.execute(
        "UPDATE feeds SET last_synced_at = ?1, last_error = NULL, error_count = 0
         WHERE id = ?2",
        params![Utc::now().timestamp_millis(), feed_id],
    )?;
    Ok(())
}

/// Records a failed sync: stamps `last_synced_at`, stores the error message in
/// `last_error`, and increments `error_count`.
pub fn record_sync_error(
    conn: &Connection,
    feed_id: &str,
    message: &str,
) -> Result<(), AppError> {
    conn.execute(
        "UPDATE feeds SET last_synced_at = ?1, last_error = ?2, error_count = error_count + 1
         WHERE id = ?3",
        params![Utc::now().timestamp_millis(), message, feed_id],
    )?;
    Ok(())
}

// --- row mapper + helpers --------------------------------------------------

fn feed_from_row(row: &Row) -> Result<Feed, rusqlite::Error> {
    let last_synced_ms: Option<i64> = row.get("last_synced_at")?;
    let last_synced_at = last_synced_ms
        .and_then(DateTime::from_timestamp_millis)
        .map(|dt| dt.to_rfc3339());
    let view_mode_str: String = row.get("article_view_mode")?;
    Ok(Feed {
        id: row.get("id")?,
        title: row.get("title")?,
        source_url: row.get("source_url")?,
        site_url: row.get::<_, Option<String>>("site_url")?.unwrap_or_default(),
        description: row.get::<_, Option<String>>("description")?.unwrap_or_default(),
        unread_count: row.get("unread_count")?,
        article_count: row.get("article_count")?,
        last_synced_at,
        article_view_mode: parse_view_mode(&view_mode_str),
        last_error: row.get("last_error")?,
        error_count: row.get("error_count")?,
    })
}

fn parse_view_mode(s: &str) -> ArticleViewMode {
    match s {
        "webpage" => ArticleViewMode::Webpage,
        "rendered" => ArticleViewMode::Rendered,
        "external" => ArticleViewMode::External,
        _ => ArticleViewMode::Global,
    }
}

fn view_mode_str(mode: &ArticleViewMode) -> &'static str {
    match mode {
        ArticleViewMode::Global => "global",
        ArticleViewMode::Webpage => "webpage",
        ArticleViewMode::Rendered => "rendered",
        ArticleViewMode::External => "external",
    }
}

fn parse_iso_to_ms(s: &str) -> Option<i64> {
    DateTime::parse_from_rfc3339(s)
        .ok()
        .map(|dt| dt.with_timezone(&Utc).timestamp_millis())
}
