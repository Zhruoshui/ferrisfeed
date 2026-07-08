//! Entry repository: CRUD for the `entries` table.
//!
//! Uses the already-FRB-exposed `crate::api::types::{Entry, EntryDraft,
//! EntryListItem}` DTOs (no name clash with `reader.rs`, which exposes
//! `Article`). Dates are stored as epoch-millis `INTEGER`. The P0b schema has
//! `guid` and `media` columns (for future P1b feed-parse/dedup use) but the
//! DTOs do not yet carry those fields, so they are written `NULL` and ignored
//! on read.

use chrono::{DateTime, Utc};
use rusqlite::{params, Connection, Row};
use uuid::Uuid;

use crate::api::types::{AdjacentEntries, Entry, EntryDraft, EntryListItem};
use crate::api::AppError;
use crate::db::repositories;

pub fn get_entry_by_id(conn: &Connection, id: &str) -> Result<Entry, AppError> {
    let mut stmt = conn.prepare("SELECT * FROM entries WHERE id = ?1")?;
    let mut rows = stmt.query_map(params![id], entry_from_row)?;
    match rows.next() {
        Some(row) => Ok(row?),
        None => Err(AppError::not_found("entry", id)),
    }
}

/// Lists entries as lightweight list items (with the parent feed's title via a
/// LEFT JOIN), applying the optional filters. Results are newest-first.
pub fn list_entries(
    conn: &Connection,
    feed_id: Option<&str>,
    unread_only: bool,
    starred_only: bool,
    limit: i64,
    offset: i64,
) -> Result<Vec<EntryListItem>, AppError> {
    let mut stmt = conn.prepare(
        "SELECT e.id, e.feed_id, f.title AS feed_title, e.title, e.summary,
                e.published_at, e.is_read, e.is_starred
         FROM entries e
         LEFT JOIN feeds f ON f.id = e.feed_id
         WHERE (?1 IS NULL OR e.feed_id = ?1)
           AND (?2 = 0 OR e.is_read = 0)
           AND (?3 = 0 OR e.is_starred = 1)
         ORDER BY e.published_at DESC, e.id DESC
         LIMIT ?4 OFFSET ?5",
    )?;
    let rows = stmt.query_map(
        params![feed_id, unread_only as i64, starred_only as i64, limit, offset],
        entry_list_item_from_row,
    )?;
    Ok(rows.collect::<Result<Vec<_>, _>>()?)
}

/// Inserts new entries for a feed, skipping drafts whose `url` already exists
/// for that feed (dedup by URL, mirroring Livo's snapshot prototype). Returns
/// the number of entries actually inserted. Recomputes the feed's cached
/// counts afterwards.
pub fn upsert_entries(
    conn: &Connection,
    feed_id: &str,
    drafts: &[EntryDraft],
) -> Result<i32, AppError> {
    let now_ms = Utc::now().timestamp_millis();
    let mut inserted = 0;
    for draft in drafts {
        let exists: bool = conn
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM entries WHERE feed_id = ?1 AND url = ?2)",
                params![feed_id, draft.url],
                |row| row.get::<_, i64>(0),
            )?
            != 0;
        if exists {
            continue;
        }
        let id = Uuid::new_v4().to_string();
        let published_ms = draft
            .published_at
            .map(|dt| dt.timestamp_millis())
            .unwrap_or(now_ms);
        conn.execute(
            "INSERT INTO entries
                (id, feed_id, title, url, author, summary, content,
                 published_at, is_read, is_starred, guid, media, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 0, 0, NULL, NULL, ?9)",
            params![
                id,
                feed_id,
                draft.title,
                draft.url,
                draft.author,
                draft.summary,
                draft.content,
                published_ms,
                now_ms,
            ],
        )?;
        inserted += 1;
    }
    repositories::feed::recompute_feed_counts(conn, feed_id)?;
    Ok(inserted)
}

pub fn mark_entry_read(conn: &Connection, id: &str, is_read: bool) -> Result<(), AppError> {
    let affected = conn.execute(
        "UPDATE entries SET is_read = ?1 WHERE id = ?2",
        params![is_read as i64, id],
    )?;
    if affected == 0 {
        return Err(AppError::not_found("entry", id));
    }
    let feed_id: String = conn.query_row(
        "SELECT feed_id FROM entries WHERE id = ?1",
        params![id],
        |row| row.get(0),
    )?;
    repositories::feed::recompute_feed_counts(conn, &feed_id)?;
    Ok(())
}

pub fn toggle_entry_star(conn: &Connection, id: &str) -> Result<bool, AppError> {
    let affected =
        conn.execute("UPDATE entries SET is_starred = 1 - is_starred WHERE id = ?1", params![id])?;
    if affected == 0 {
        return Err(AppError::not_found("entry", id));
    }
    let is_starred: bool = conn.query_row(
        "SELECT is_starred FROM entries WHERE id = ?1",
        params![id],
        |row| row.get::<_, i64>(0).map(|v| v != 0),
    )?;
    Ok(is_starred)
}

/// Returns the previous (newer) and next (older) entry ids relative to `id`,
/// within the same filter context. The entry list is ordered by
/// `published_at DESC, id DESC` (newest-first), so `prev` is the neighbour
/// with a greater `(published_at, id)` tuple and `next` is the neighbour with
/// a smaller one. Either is `None` at the ends of the list or when `id` itself
/// is not found / filtered out.
pub fn get_adjacent_entries(
    conn: &Connection,
    id: &str,
    feed_id: Option<&str>,
    unread_only: bool,
    starred_only: bool,
) -> Result<AdjacentEntries, AppError> {
    // Need the current entry's published_at to compare tuples.
    let current_ms: Option<i64> = conn
        .query_row(
            "SELECT published_at FROM entries WHERE id = ?1",
            params![id],
            |row| row.get::<_, i64>(0),
        )
        .ok();
    let Some(current_ms) = current_ms else {
        return Ok(AdjacentEntries {
            prev: None,
            next: None,
        });
    };

    // prev = newest-first neighbour above the current row (newer): strictly
    // greater (published_at, id) tuple.
    let prev = conn
        .query_row(
            "SELECT e.id FROM entries e
             WHERE (?1 IS NULL OR e.feed_id = ?1)
               AND (?2 = 0 OR e.is_read = 0)
               AND (?3 = 0 OR e.is_starred = 1)
               AND (e.published_at > ?4 OR (e.published_at = ?4 AND e.id > ?5))
             ORDER BY e.published_at ASC, e.id ASC
             LIMIT 1",
            params![feed_id, unread_only as i64, starred_only as i64, current_ms, id],
            |row| row.get::<_, String>(0),
        )
        .ok();

    // next = newest-first neighbour below the current row (older): strictly
    // smaller (published_at, id) tuple.
    let next = conn
        .query_row(
            "SELECT e.id FROM entries e
             WHERE (?1 IS NULL OR e.feed_id = ?1)
               AND (?2 = 0 OR e.is_read = 0)
               AND (?3 = 0 OR e.is_starred = 1)
               AND (e.published_at < ?4 OR (e.published_at = ?4 AND e.id < ?5))
             ORDER BY e.published_at DESC, e.id DESC
             LIMIT 1",
            params![feed_id, unread_only as i64, starred_only as i64, current_ms, id],
            |row| row.get::<_, String>(0),
        )
        .ok();

    Ok(AdjacentEntries { prev, next })
}

/// Marks all entries as read, optionally scoped to one feed, and recomputes
/// the affected feeds' cached counts.
pub fn mark_all_read(conn: &Connection, feed_id: Option<&str>) -> Result<(), AppError> {
    conn.execute(
        "UPDATE entries SET is_read = 1 WHERE (?1 IS NULL OR feed_id = ?1)",
        params![feed_id],
    )?;
    let feed_ids: Vec<String> = match feed_id {
        Some(fid) => vec![fid.to_owned()],
        None => {
            let mut stmt = conn.prepare("SELECT id FROM feeds")?;
            let rows = stmt.query_map([], |row| row.get::<_, String>(0))?;
            rows.collect::<Result<Vec<_>, _>>()?
        }
    };
    for fid in feed_ids {
        repositories::feed::recompute_feed_counts(conn, &fid)?;
    }
    Ok(())
}

// --- P1b: sync upsert (guid idempotency + media) ---------------------------

/// Content needed to compute a simhash fingerprint for an existing entry.
/// Loaded by [`list_entries_for_dedup`] so the sync dedup logic (in `feed/`)
/// can near-duplicate-check new drafts against what is already stored.
pub struct EntryDedupData {
    pub id: String,
    pub title: String,
    pub url: String,
    pub guid: Option<String>,
    pub summary: Option<String>,
    pub content: Option<String>,
}

/// Loads the dedup-relevant fields for every entry in a feed (newest-first is
/// not required; the simhash check scans all of them). Used by the sync path
/// to (a) guard idempotent upsert by guid/url and (b) compute near-dup
/// fingerprints for the incoming drafts.
pub fn list_entries_for_dedup(
    conn: &Connection,
    feed_id: &str,
) -> Result<Vec<EntryDedupData>, AppError> {
    let mut stmt = conn.prepare(
        "SELECT id, title, url, guid, summary, content
         FROM entries WHERE feed_id = ?1",
    )?;
    let rows = stmt.query_map(params![feed_id], |row| {
        Ok(EntryDedupData {
            id: row.get("id")?,
            title: row.get::<_, Option<String>>("title")?.unwrap_or_default(),
            url: row.get::<_, Option<String>>("url")?.unwrap_or_default(),
            guid: row.get("guid")?,
            summary: row.get("summary")?,
            content: row.get("content")?,
        })
    })?;
    Ok(rows.collect::<Result<Vec<_>, _>>()?)
}

/// The fields required to insert one synced entry, including the `guid` and
/// `media` columns that P0b left NULL. Lives in the `db` layer (with borrowed
/// fields) so the repository does not depend on `feed/`.
pub struct SyncedEntryRecord<'a> {
    pub id: &'a str,
    pub feed_id: &'a str,
    pub title: &'a str,
    pub url: &'a str,
    pub author: Option<&'a str>,
    pub summary: Option<&'a str>,
    pub content: Option<&'a str>,
    pub published_ms: i64,
    pub guid: Option<&'a str>,
    pub media_json: Option<&'a str>,
}

/// Inserts a single synced entry with the `guid` and `media` columns populated.
/// The caller is responsible for idempotency / near-dup checks before calling;
/// this performs a plain INSERT. Callers should recompute feed counts after a
/// batch of inserts.
pub fn insert_synced_entry(conn: &Connection, rec: &SyncedEntryRecord) -> Result<(), AppError> {
    let now_ms = Utc::now().timestamp_millis();
    conn.execute(
        "INSERT INTO entries
            (id, feed_id, title, url, author, summary, content,
             published_at, is_read, is_starred, guid, media, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 0, 0, ?9, ?10, ?11)",
        params![
            rec.id,
            rec.feed_id,
            rec.title,
            rec.url,
            rec.author,
            rec.summary,
            rec.content,
            rec.published_ms,
            rec.guid,
            rec.media_json,
            now_ms,
        ],
    )?;
    Ok(())
}

// --- row mappers -----------------------------------------------------------

fn entry_from_row(row: &Row) -> Result<Entry, rusqlite::Error> {
    let published_ms: i64 = row.get("published_at")?;
    let created_ms: i64 = row.get("created_at")?;
    Ok(Entry {
        id: row.get("id")?,
        feed_id: row.get("feed_id")?,
        title: row.get("title")?,
        url: row.get("url")?,
        content: row.get("content")?,
        summary: row.get("summary")?,
        author: row.get("author")?,
        // image_url / read_progress have no P0b columns yet.
        image_url: None,
        published_at: DateTime::from_timestamp_millis(published_ms).unwrap_or_else(Utc::now),
        is_read: row.get::<_, i64>("is_read")? != 0,
        is_starred: row.get::<_, i64>("is_starred")? != 0,
        read_progress: None,
        created_at: DateTime::from_timestamp_millis(created_ms).unwrap_or_else(Utc::now),
    })
}

fn entry_list_item_from_row(row: &Row) -> Result<EntryListItem, rusqlite::Error> {
    let published_ms: Option<i64> = row.get("published_at")?;
    Ok(EntryListItem {
        id: row.get("id")?,
        feed_id: row.get("feed_id")?,
        feed_title: row
            .get::<_, Option<String>>("feed_title")?
            .unwrap_or_default(),
        title: row.get("title")?,
        summary: row.get::<_, Option<String>>("summary")?.unwrap_or_default(),
        published_at: published_ms.and_then(DateTime::from_timestamp_millis),
        is_read: row.get::<_, i64>("is_read")? != 0,
        is_starred: row.get::<_, i64>("is_starred")? != 0,
    })
}
