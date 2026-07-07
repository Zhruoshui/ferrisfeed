//! Feed sync orchestration: fetch + parse + idempotent upsert + simhash dedup.
//!
//! `sync_feeds_impl` drives a refresh over a set of feed ids, emitting a
//! [`SyncProgress`] event per feed (success or failure) plus a final summary
//! event. Per-feed failures (network, parse, DB) are isolated: the failing feed
//! records its error on the `feeds` row and the sync continues with the next
//! feed — the whole run only fails for catastrophic setup errors.
//!
//! Layering: this module (in `feed/`) is the orchestrator. It calls
//! `feed::{fetch, parse, simhash}` for the network/CPU work and
//! `db::repositories::{entry, feed}` for persistence. Third-party types never
//! cross the FRB boundary (the `api/feed.rs` wrappers convert to DTOs).

use chrono::{DateTime, Utc};
use uuid::Uuid;

use crate::api::types::SyncProgress;
use crate::api::AppError;
use crate::db::connection::with_db;
use crate::db::repositories;
use crate::feed::{fetch, parse, simhash};
use crate::frb_generated::StreamSink;

/// A parsed entry flattened into the fields the upsert path needs (including
/// `guid` + serialized `media`, which P0b left NULL).
struct SyncEntryDraft {
    title: String,
    url: String,
    guid: String,
    author: Option<String>,
    summary: Option<String>,
    content: Option<String>,
    published_at: Option<DateTime<Utc>>,
    media_json: Option<String>,
}

/// Drives a refresh over `feed_ids`, pushing per-feed progress to `sink`.
///
/// Returns `Ok(())` when every feed has been attempted (failures are embedded
/// in the progress events and recorded on the feed rows). The final progress
/// event (`done = true`) carries the cumulative totals; Dart reads the summary
/// from there since FRB stream-sink functions cannot return a value.
pub(crate) async fn sync_feeds_impl(
    sink: StreamSink<SyncProgress>,
    feed_ids: Vec<String>,
) -> Result<(), AppError> {
    let total = feed_ids.len() as i32;
    let mut completed = 0i32;
    let mut failed = 0i32;
    let mut total_new_entries = 0i32;

    for feed_id in &feed_ids {
        let (new_entries, feed_title, error) = sync_one_feed(feed_id).await;
        completed += 1;
        if error.is_some() {
            failed += 1;
        } else {
            total_new_entries += new_entries;
        }
        let _ = sink.add(SyncProgress {
            total,
            completed,
            failed,
            feed_id: Some(feed_id.clone()),
            feed_title,
            new_entries,
            total_new_entries,
            done: false,
            error,
        });
    }

    // Final summary event.
    let _ = sink.add(SyncProgress {
        total,
        completed,
        failed,
        feed_id: None,
        feed_title: None,
        new_entries: 0,
        total_new_entries,
        done: true,
        error: None,
    });
    Ok(())
}

/// Syncs a single feed (no stream). Returns the per-feed new-entry count. A
/// network/parse failure is recorded on the feed row (last_error / error_count)
/// and then surfaced as `Err` (there is only one feed, so isolation is moot).
pub(crate) async fn refresh_feed_impl(feed_id: String) -> Result<i32, AppError> {
    let feed = with_db(|conn| repositories::feed::get_feed_by_id(conn, &feed_id))?
        .ok_or_else(|| AppError::not_found("feed", &feed_id))?;
    match fetch_parse_upsert(&feed.id, &feed.source_url).await {
        Ok(new_entries) => {
            with_db(|conn| repositories::feed::record_sync_success(conn, &feed.id))?;
            Ok(new_entries)
        }
        Err(e) => {
            let msg = e.to_string();
            let _ = with_db(|conn| repositories::feed::record_sync_error(conn, &feed.id, &msg));
            Err(e)
        }
    }
}

/// Fetches, parses, dedups, and upserts one feed. Returns the new-entry count
/// and the feed title on success, or the error + feed title (when known) on
/// failure. The caller records the outcome on the feed row.
async fn sync_one_feed(feed_id: &str) -> (i32, Option<String>, Option<String>) {
    // Load the feed (best-effort): we need the source URL and want the title for
    // progress display even when the fetch/parse fails.
    let feed = match with_db(|conn| repositories::feed::get_feed_by_id(conn, feed_id)) {
        Ok(Some(f)) => f,
        Ok(None) => {
            return (
                0,
                None,
                Some(format!("feed not found: {feed_id}")),
            );
        }
        Err(e) => {
            return (0, None, Some(e.to_string()));
        }
    };
    let title = feed.title.clone();
    let url = feed.source_url.clone();

    match fetch_parse_upsert(feed_id, &url).await {
        Ok(new_entries) => {
            let _ = with_db(|conn| repositories::feed::record_sync_success(conn, feed_id));
            (new_entries, Some(title), None)
        }
        Err(e) => {
            let msg = e.to_string();
            let _ = with_db(|conn| {
                repositories::feed::record_sync_error(conn, feed_id, &msg)
            });
            (0, Some(title), Some(msg))
        }
    }
}

/// Fetches + parses `source_url`, then dedups + upserts the entries into the
/// feed identified by `feed_id`. Returns the number of newly inserted entries.
async fn fetch_parse_upsert(feed_id: &str, source_url: &str) -> Result<i32, AppError> {
    let (bytes, _content_type) = fetch::fetch_url(source_url).await?;
    let parsed = parse::parse_feed(&bytes, source_url)?;

    let drafts: Vec<SyncEntryDraft> = parsed.entries.into_iter().map(to_sync_draft).collect();

    // Compute simhash fingerprints for the incoming drafts OUTSIDE the DB lock
    // (CPU-bound SHA-1 work). Existing entries' fingerprints are cached and
    // looked up inside the lock, so the lock is held only for short DB work.
    let draft_fps: Vec<Option<u64>> = drafts
        .iter()
        .map(|d| {
            simhash::compute(&simhash::SimhashInput {
                id: None,
                title: &d.title,
                summary: d.summary.as_deref(),
                content: d.content.as_deref(),
            })
        })
        .collect();

    with_db(|conn| dedup_and_insert(conn, feed_id, &drafts, &draft_fps))
}

/// The DB-bound core of a sync upsert: loads existing entries, computes (cached)
/// fingerprints for them, then for each draft applies the idempotent guid/url
/// guard and the simhash near-dup guard before inserting. Recomputes the feed's
/// cached counts. Separated from [`fetch_parse_upsert`] so it can be tested
/// against an in-memory database without any network I/O.
fn dedup_and_insert(
    conn: &rusqlite::Connection,
    feed_id: &str,
    drafts: &[SyncEntryDraft],
    draft_fps: &[Option<u64>],
) -> Result<i32, AppError> {
    let existing = repositories::entry::list_entries_for_dedup(conn, feed_id)?;
    // Existing fingerprints (cached -> cheap on repeat syncs).
    let mut accepted_fps: Vec<Option<u64>> = existing
        .iter()
        .map(|e| {
            simhash::compute(&simhash::SimhashInput {
                id: Some(&e.id),
                title: &e.title,
                summary: e.summary.as_deref(),
                content: e.content.as_deref(),
            })
        })
        .collect();

    let mut inserted = 0i32;
    for (draft, fp) in drafts.iter().zip(draft_fps.iter()) {
        // Idempotent: skip if an existing entry shares the dedup key
        // (guid, falling back to url) or the url.
        if is_duplicate_of_existing(&existing, draft) {
            continue;
        }
        // Near-duplicate: skip if the fingerprint is within the Hamming
        // threshold of any already-accepted entry (existing or new).
        if let Some(fp) = fp {
            if accepted_fps
                .iter()
                .flatten()
                .any(|g| simhash::is_near_duplicate(*fp, *g))
            {
                continue;
            }
        }
        let id = Uuid::new_v4().to_string();
        repositories::entry::insert_synced_entry(
            conn,
            &repositories::entry::SyncedEntryRecord {
                id: &id,
                feed_id,
                title: &draft.title,
                url: &draft.url,
                author: draft.author.as_deref(),
                summary: draft.summary.as_deref(),
                content: draft.content.as_deref(),
                published_ms: draft
                    .published_at
                    .map(|dt| dt.timestamp_millis())
                    .unwrap_or_else(|| Utc::now().timestamp_millis()),
                guid: Some(&draft.guid),
                media_json: draft.media_json.as_deref(),
            },
        )?;
        accepted_fps.push(*fp);
        inserted += 1;
    }

    repositories::feed::recompute_feed_counts(conn, feed_id)?;
    Ok(inserted)
}

/// True when `draft` matches an existing entry by dedup key (guid fallback url)
/// or by url — the idempotent upsert guard so re-running a sync creates no
/// duplicate rows.
fn is_duplicate_of_existing(
    existing: &[repositories::entry::EntryDedupData],
    draft: &SyncEntryDraft,
) -> bool {
    existing.iter().any(|e| {
        let e_key = e
            .guid
            .as_deref()
            .filter(|g| !g.is_empty())
            .unwrap_or(&e.url);
        let d_key = if draft.guid.is_empty() {
            &draft.url
        } else {
            &draft.guid
        };
        (!d_key.is_empty() && e_key == d_key) || (!e.url.is_empty() && e.url == draft.url)
    })
}

/// Converts a parsed entry into the fields the upsert needs. The `guid`
/// column is the parsed entry id when present, otherwise the url, so the dedup
/// key is always populated.
fn to_sync_draft(e: parse::ParsedEntry) -> SyncEntryDraft {
    let guid = {
        let g = e.guid.as_deref().unwrap_or("").trim();
        if g.is_empty() {
            e.url.clone()
        } else {
            g.to_string()
        }
    };
    let media_json = if e.media.is_empty() {
        None
    } else {
        serde_json::to_string(&e.media).ok()
    };
    SyncEntryDraft {
        title: e.title,
        url: e.url,
        guid,
        author: e.author,
        summary: e.summary,
        content: e.content,
        published_at: e.published_at,
        media_json,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::feed::parse::{MediaItem, ParsedEntry};

    fn parsed(title: &str, url: &str, guid: Option<&str>, content: Option<&str>) -> ParsedEntry {
        ParsedEntry {
            title: title.to_string(),
            url: url.to_string(),
            guid: guid.map(|s| s.to_string()),
            author: None,
            summary: None,
            content: content.map(|s| s.to_string()),
            published_at: None,
            media: Vec::new(),
        }
    }

    #[test]
    fn to_sync_draft_uses_guid_when_present() {
        let draft = to_sync_draft(parsed("t", "https://a/1", Some("guid-1"), None));
        assert_eq!(draft.guid, "guid-1");
    }

    #[test]
    fn to_sync_draft_falls_back_to_url_when_guid_empty() {
        let draft = to_sync_draft(parsed("t", "https://a/1", None, None));
        assert_eq!(draft.guid, "https://a/1");
    }

    #[test]
    fn to_sync_draft_serializes_media() {
        let mut entry = parsed("t", "https://a/1", Some("g"), None);
        entry.media.push(MediaItem {
            url: "https://a/img.jpg".to_string(),
            mime_type: Some("image/jpeg".to_string()),
            kind: None,
        });
        let draft = to_sync_draft(entry);
        let json = draft.media_json.unwrap();
        assert!(json.contains("https://a/img.jpg"));
        assert!(json.contains("image/jpeg"));
    }

    #[test]
    fn to_sync_draft_omits_media_json_when_empty() {
        let draft = to_sync_draft(parsed("t", "https://a/1", Some("g"), None));
        assert!(draft.media_json.is_none());
    }

    #[test]
    fn duplicate_detection_matches_by_guid() {
        let existing = vec![repositories::entry::EntryDedupData {
            id: "e1".to_string(),
            title: "old".to_string(),
            url: "https://a/1".to_string(),
            guid: Some("guid-1".to_string()),
            summary: None,
            content: None,
        }];
        // Same guid, different url -> duplicate.
        let draft = to_sync_draft(parsed("t", "https://a/other", Some("guid-1"), None));
        assert!(is_duplicate_of_existing(&existing, &draft));
    }

    #[test]
    fn duplicate_detection_matches_by_url_when_guid_differs() {
        let existing = vec![repositories::entry::EntryDedupData {
            id: "e1".to_string(),
            title: "old".to_string(),
            url: "https://a/1".to_string(),
            guid: Some("guid-old".to_string()),
            summary: None,
            content: None,
        }];
        // Different guid, same url -> duplicate.
        let draft = to_sync_draft(parsed("t", "https://a/1", Some("guid-new"), None));
        assert!(is_duplicate_of_existing(&existing, &draft));
    }

    #[test]
    fn duplicate_detection_skips_when_distinct() {
        let existing = vec![repositories::entry::EntryDedupData {
            id: "e1".to_string(),
            title: "old".to_string(),
            url: "https://a/1".to_string(),
            guid: Some("guid-old".to_string()),
            summary: None,
            content: None,
        }];
        let draft = to_sync_draft(parsed("t", "https://a/2", Some("guid-new"), None));
        assert!(!is_duplicate_of_existing(&existing, &draft));
    }

    // --- dedup_and_insert integration tests (in-memory DB, no network) -------

    use crate::api::reader::{ArticleViewMode, Feed};
    use rusqlite::Connection;

    /// A fresh in-memory database with the MVP schema + FK enforcement, matching
    /// `db::repositories::tests::test_db` (duplicated here so `feed::sync` tests
    /// stay self-contained without crossing into the `db` test module).
    fn test_db() -> Connection {
        let mut conn = Connection::open_in_memory().unwrap();
        conn.pragma_update(None, "foreign_keys", "ON").unwrap();
        crate::db::migrations::run(&mut conn).unwrap();
        conn
    }

    fn sample_feed(id: &str, url: &str) -> Feed {
        Feed {
            id: id.to_owned(),
            title: format!("Feed {id}"),
            source_url: url.to_owned(),
            site_url: "https://example.com".to_owned(),
            description: "desc".to_owned(),
            unread_count: 0,
            article_count: 0,
            last_synced_at: None,
            article_view_mode: ArticleViewMode::default(),
            last_error: None,
            error_count: 0,
        }
    }

    /// Enough text to clear the 18-token simhash minimum.
    const LONG_CONTENT_A: &str = "The quick brown fox jumps over the lazy dog near the \
                                   riverbank on a sunny afternoon while the children watch \
                                   in amazement and the parents take photographs of the scene";
    /// Near-duplicate of A (differs by a trailing word) — used to exercise the
    /// simhash near-dup guard.
    const LONG_CONTENT_A_VARIANT: &str = "The quick brown fox jumps over the lazy dog near the \
                                   riverbank on a sunny afternoon while the children watch \
                                   in amazement and the parents take photographs of the scene \
                                   developing today";
    /// Unrelated text (different topic) — should NOT be flagged as a near-dup.
    const LONG_CONTENT_UNRELATED: &str = "Completely different topic about space exploration \
                                   missions to distant planets with new rocket technology \
                                   enabling faster travel than ever before in human history";

    fn draft_fps(drafts: &[SyncEntryDraft]) -> Vec<Option<u64>> {
        drafts
            .iter()
            .map(|d| {
                simhash::compute(&simhash::SimhashInput {
                    id: None,
                    title: &d.title,
                    summary: d.summary.as_deref(),
                    content: d.content.as_deref(),
                })
            })
            .collect()
    }

    #[test]
    fn dedup_and_insert_is_idempotent_by_guid() {
        let conn = test_db();
        repositories::feed::upsert_feed(&conn, &sample_feed("f1", "https://a/feed")).unwrap();

        // Two entries with unrelated content (so simhash does not skip either)
        // and distinct guids.
        let drafts = vec![
            to_sync_draft(parsed("First", "https://a/1", Some("g1"), Some(LONG_CONTENT_A))),
            to_sync_draft(parsed("Second", "https://a/2", Some("g2"), Some(LONG_CONTENT_UNRELATED))),
        ];
        let fps = draft_fps(&drafts);

        // First sync: both insert.
        let inserted = dedup_and_insert(&conn, "f1", &drafts, &fps).unwrap();
        assert_eq!(inserted, 2);

        // Re-sync with the same guids: nothing inserts (idempotent).
        let inserted_again = dedup_and_insert(&conn, "f1", &drafts, &fps).unwrap();
        assert_eq!(inserted_again, 0);

        // Still only two rows, and feed counts are correct.
        let existing = repositories::entry::list_entries_for_dedup(&conn, "f1").unwrap();
        assert_eq!(existing.len(), 2);
        let feed = repositories::feed::get_feed_by_id(&conn, "f1").unwrap().unwrap();
        assert_eq!(feed.article_count, 2);
    }

    #[test]
    fn dedup_and_insert_skips_near_duplicate_content() {
        let conn = test_db();
        repositories::feed::upsert_feed(&conn, &sample_feed("f1", "https://a/feed")).unwrap();

        // Insert one entry with content A.
        let first = vec![to_sync_draft(parsed(
            "Fox sighting reported",
            "https://a/1",
            Some("g1"),
            Some(LONG_CONTENT_A),
        ))];
        let inserted = dedup_and_insert(&conn, "f1", &first, &draft_fps(&first)).unwrap();
        assert_eq!(inserted, 1);

        // A second entry with a DIFFERENT guid/url but NEAR-DUPLICATE content
        // (A_VARIANT differs from A by one trailing word) must be skipped.
        let near_dup = vec![to_sync_draft(parsed(
            "Fox sighting reported",
            "https://a/2",
            Some("g2"),
            Some(LONG_CONTENT_A_VARIANT),
        ))];
        let inserted = dedup_and_insert(&conn, "f1", &near_dup, &draft_fps(&near_dup)).unwrap();
        assert_eq!(
            inserted, 0,
            "near-duplicate content should be skipped by simhash"
        );

        // Only one entry persisted.
        let existing = repositories::entry::list_entries_for_dedup(&conn, "f1").unwrap();
        assert_eq!(existing.len(), 1);
    }

    #[test]
    fn dedup_and_insert_fills_guid_and_media_columns() {
        let conn = test_db();
        repositories::feed::upsert_feed(&conn, &sample_feed("f1", "https://a/feed")).unwrap();

        let mut entry = parsed("With media", "https://a/1", Some("guid-1"), Some(LONG_CONTENT_A));
        entry.media.push(MediaItem {
            url: "https://a/img.jpg".to_string(),
            mime_type: Some("image/jpeg".to_string()),
            kind: Some("thumbnail".to_string()),
        });
        let drafts = vec![to_sync_draft(entry)];
        let inserted = dedup_and_insert(&conn, "f1", &drafts, &draft_fps(&drafts)).unwrap();
        assert_eq!(inserted, 1);

        // The guid + media columns were populated (P0b left them NULL).
        let row = conn
            .query_row(
                "SELECT guid, media FROM entries WHERE feed_id = ?1",
                rusqlite::params!["f1"],
                |r| Ok((r.get::<_, Option<String>>(0)?, r.get::<_, Option<String>>(1)?)),
            )
            .unwrap();
        assert_eq!(row.0.as_deref(), Some("guid-1"));
        let media = row.1.unwrap();
        assert!(media.contains("https://a/img.jpg"));
        assert!(media.contains("thumbnail"));
    }

    #[test]
    fn dedup_and_insert_accepts_unrelated_entries() {
        let conn = test_db();
        repositories::feed::upsert_feed(&conn, &sample_feed("f1", "https://a/feed")).unwrap();

        let drafts = vec![
            to_sync_draft(parsed("Tech news", "https://a/1", Some("g1"), Some(LONG_CONTENT_A))),
            to_sync_draft(parsed("Space news", "https://a/2", Some("g2"), Some(LONG_CONTENT_UNRELATED))),
        ];
        let inserted = dedup_and_insert(&conn, "f1", &drafts, &draft_fps(&drafts)).unwrap();
        assert_eq!(inserted, 2, "unrelated entries should both be accepted");
    }

    // --- End-to-end network smoke test (ignored; run with --ignored) ----------
    //
    // Exercises the full `refresh_feed_impl` path: subscribe (metadata) ->
    // refresh (fetch + parse + idempotent upsert + simhash) -> re-refresh
    // (idempotent, no dups). Uses the global `with_db` connection, so it
    // initializes the DB itself (ignoring "already initialized" if another test
    // ran first in the same process). Network-dependent — skipped by default.

    #[tokio::test]
    #[ignore = "requires network; run with --ignored"]
    async fn refresh_real_feed_end_to_end() {
        use crate::db::connection::{init_db, with_db};

        let path = std::env::temp_dir()
            .join(format!("rss_reader_p1b_smoke_{}.db", std::process::id()));
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(path.with_extension("db-wal"));
        let _ = std::fs::remove_file(path.with_extension("db-shm"));
        // Ignore "already initialized" — the OnceLock is process-global.
        let _ = init_db(path.to_str().unwrap());

        // Subscribe to BBC (creates the feed row with metadata only).
        let feed = crate::feed::subscribe_feed_impl("https://feeds.bbci.co.uk/news/rss.xml")
            .await
            .expect("subscribe failed");

        // First refresh: fetch + parse + upsert entries.
        let first = refresh_feed_impl(feed.id.clone())
            .await
            .expect("first refresh failed");
        eprintln!("first refresh inserted {first} entries");
        assert!(first > 0, "first refresh should insert entries");

        // Re-refresh: idempotent — same guids, no new entries.
        let second = refresh_feed_impl(feed.id.clone())
            .await
            .expect("second refresh failed");
        eprintln!("second refresh inserted {second} entries");
        assert_eq!(second, 0, "re-refresh should insert nothing (idempotent)");

        // The entry count is stable across refreshes.
        let count = with_db(|conn| {
            repositories::entry::list_entries_for_dedup(conn, &feed.id).map(|v| v.len())
        })
        .expect("list failed");
        eprintln!("persisted {count} entries for feed {}", feed.id);
        assert_eq!(count as i32, first, "entry count should match first insert");

        // Every entry has a non-empty guid (the idempotency key).
        let guids = with_db(|conn| {
            let existing = repositories::entry::list_entries_for_dedup(conn, &feed.id)?;
            Ok::<_, AppError>(
                existing
                    .iter()
                    .filter(|e| e.guid.as_deref().unwrap_or("").is_empty())
                    .count(),
            )
        })
        .expect("guid check failed");
        assert_eq!(guids, 0, "every synced entry should have a guid");

        // Best-effort cleanup.
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(path.with_extension("db-wal"));
        let _ = std::fs::remove_file(path.with_extension("db-shm"));
    }
}
