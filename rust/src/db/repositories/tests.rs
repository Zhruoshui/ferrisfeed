//! Repository unit tests against an in-memory SQLite database.
//!
//! These exercise the row mappers, CRUD, filters, FK cascade, and count
//! recompute without touching the global `OnceLock` connection (which can only
//! be initialized once per process). Each test builds a fresh in-memory DB with
//! migrations applied and `foreign_keys=ON`.

use chrono::{DateTime, Utc};
use rusqlite::Connection;

use crate::api::types::{ArticleViewMode, EntryDraft, Feed};
use crate::api::AppError;
use crate::db::repositories::{category, entry, feed};

/// A fresh in-memory database with the MVP schema and FK enforcement on.
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
        site_url: Some("https://example.com".to_owned()),
        description: Some("desc".to_owned()),
        image_url: None,
        folder: None,
        category: None,
        article_view_mode: ArticleViewMode::default(),
        unread_count: 0,
        article_count: 0,
        last_synced_at: None,
        last_error: None,
        error_count: 0,
        etag: None,
        last_modified: None,
        created_at: Utc::now(),
    }
}

fn draft(title: &str, url: &str) -> EntryDraft {
    EntryDraft {
        title: title.to_owned(),
        url: url.to_owned(),
        author: Some("Author".to_owned()),
        summary: Some("summary".to_owned()),
        content: Some("content".to_owned()),
        published_at: Some(Utc::now()),
    }
}

/// Like [`draft`] but with an explicit publish time (epoch-millis), so
/// pagination / adjacent-entry tests get a deterministic newest-first order.
fn draft_at(title: &str, url: &str, published_ms: i64) -> EntryDraft {
    EntryDraft {
        title: title.to_owned(),
        url: url.to_owned(),
        author: Some("Author".to_owned()),
        summary: Some("summary".to_owned()),
        content: Some("content".to_owned()),
        published_at: DateTime::from_timestamp_millis(published_ms),
    }
}

#[test]
fn feed_upsert_list_get_roundtrip() {
    let conn = test_db();
    let mut feed = sample_feed("f1", "https://example.com/feed.xml");
    feed::upsert_feed(&conn, &feed).unwrap();

    let listed = feed::list_feeds(&conn).unwrap();
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0].id, "f1");
    assert_eq!(listed[0].title, "Feed f1");

    let fetched = feed::get_feed_by_id(&conn, "f1").unwrap().unwrap();
    assert_eq!(fetched.source_url, "https://example.com/feed.xml");
    assert_eq!(fetched.article_view_mode, ArticleViewMode::Global);

    // Update via upsert changes the title but keeps created_at.
    feed.title = "Updated".to_owned();
    feed::upsert_feed(&conn, &feed).unwrap();
    let fetched = feed::get_feed_by_id(&conn, "f1").unwrap().unwrap();
    assert_eq!(fetched.title, "Updated");
    assert_eq!(feed::list_feeds(&conn).unwrap().len(), 1);

    // Missing feed resolves to None.
    assert!(feed::get_feed_by_id(&conn, "missing").unwrap().is_none());
}

#[test]
fn feed_view_mode_round_trips() {
    let conn = test_db();
    let feed = sample_feed("f1", "https://example.com/feed.xml");
    feed::upsert_feed(&conn, &feed).unwrap();
    feed::set_feed_view_mode(&conn, "f1", ArticleViewMode::Rendered).unwrap();
    let fetched = feed::get_feed_by_id(&conn, "f1").unwrap().unwrap();
    assert_eq!(fetched.article_view_mode, ArticleViewMode::Rendered);
}

#[test]
fn feed_delete_cascades_to_entries() {
    let conn = test_db();
    feed::upsert_feed(&conn, &sample_feed("f1", "https://a/feed")).unwrap();
    entry::upsert_entries(&conn, "f1", &[draft("a", "https://a/1"), draft("b", "https://a/2")])
        .unwrap();

    feed::delete_feed(&conn, "f1").unwrap();
    assert!(feed::get_feed_by_id(&conn, "f1").unwrap().is_none());
    // Cascade removed the entries.
    let items = entry::list_entries(&conn, None, false, false, 50, 0).unwrap();
    assert!(items.is_empty());
}

#[test]
fn entry_upsert_dedups_by_url() {
    let conn = test_db();
    feed::upsert_feed(&conn, &sample_feed("f1", "https://a/feed")).unwrap();

    let inserted = entry::upsert_entries(
        &conn,
        "f1",
        &[draft("first", "https://a/1"), draft("second", "https://a/2")],
    )
    .unwrap();
    assert_eq!(inserted, 2);

    // Re-inserting the same URLs inserts nothing.
    let inserted_again = entry::upsert_entries(
        &conn,
        "f1",
        &[draft("first", "https://a/1"), draft("third", "https://a/3")],
    )
    .unwrap();
    assert_eq!(inserted_again, 1);

    let items = entry::list_entries(&conn, None, false, false, 50, 0).unwrap();
    assert_eq!(items.len(), 3);
}

#[test]
fn entry_list_filters_and_counts() {
    let conn = test_db();
    feed::upsert_feed(&conn, &sample_feed("f1", "https://a/feed")).unwrap();
    entry::upsert_entries(
        &conn,
        "f1",
        &[draft("a", "https://a/1"), draft("b", "https://a/2")],
    )
    .unwrap();

    // Fresh entries are all unread; feed counts recompute to 2/2.
    let feed = feed::get_feed_by_id(&conn, "f1").unwrap().unwrap();
    assert_eq!(feed.article_count, 2);
    assert_eq!(feed.unread_count, 2);

    let all = entry::list_entries(&conn, None, false, false, 50, 0).unwrap();
    assert_eq!(all.len(), 2);
    let unread = entry::list_entries(&conn, None, true, false, 50, 0).unwrap();
    assert_eq!(unread.len(), 2);

    // Mark the first unread entry read.
    let first_id = all[0].id.clone();
    entry::mark_entry_read(&conn, &first_id, true).unwrap();

    let unread = entry::list_entries(&conn, None, true, false, 50, 0).unwrap();
    assert_eq!(unread.len(), 1);
    let feed = feed::get_feed_by_id(&conn, "f1").unwrap().unwrap();
    assert_eq!(feed.unread_count, 1);
    assert_eq!(feed.article_count, 2);

    // Nothing starred yet.
    let starred = entry::list_entries(&conn, None, false, true, 50, 0).unwrap();
    assert!(starred.is_empty());

    // Star the other entry.
    let other_id = all[1].id.clone();
    entry::toggle_entry_star(&conn, &other_id).unwrap();
    let starred = entry::list_entries(&conn, None, false, true, 50, 0).unwrap();
    assert_eq!(starred.len(), 1);
    assert_eq!(starred[0].id, other_id);

    // Toggling again un-stars.
    entry::toggle_entry_star(&conn, &other_id).unwrap();
    let starred = entry::list_entries(&conn, None, false, true, 50, 0).unwrap();
    assert!(starred.is_empty());
}

#[test]
fn entry_get_returns_full_content() {
    let conn = test_db();
    feed::upsert_feed(&conn, &sample_feed("f1", "https://a/feed")).unwrap();
    entry::upsert_entries(&conn, "f1", &[draft("a", "https://a/1")]).unwrap();
    let listed = entry::list_entries(&conn, None, false, false, 50, 0).unwrap();
    let full = entry::get_entry_by_id(&conn, &listed[0].id).unwrap();
    assert_eq!(full.title, "a");
    assert_eq!(full.author.as_deref(), Some("Author"));
    assert_eq!(full.content.as_deref(), Some("content"));
    assert!(!full.is_read);
}

#[test]
fn entry_get_missing_is_not_found() {
    let conn = test_db();
    feed::upsert_feed(&conn, &sample_feed("f1", "https://a/feed")).unwrap();
    match entry::get_entry_by_id(&conn, "missing") {
        Err(AppError::NotFound { resource, .. }) => assert_eq!(resource, "entry"),
        other => panic!("expected NotFound, got {other:?}"),
    }
}

#[test]
fn entry_list_paginates_with_limit_and_offset() {
    let conn = test_db();
    feed::upsert_feed(&conn, &sample_feed("f1", "https://a/feed")).unwrap();
    let drafts: Vec<EntryDraft> = (0..5)
        .map(|i| draft_at(&format!("e{i}"), &format!("https://a/{i}"), 1_000_000 + i))
        .collect();
    entry::upsert_entries(&conn, "f1", &drafts).unwrap();

    // newest-first: e4, e3, e2, e1, e0
    let page1 = entry::list_entries(&conn, None, false, false, 2, 0).unwrap();
    assert_eq!(page1.len(), 2);
    assert_eq!(page1[0].title, "e4");
    assert_eq!(page1[1].title, "e3");

    let page2 = entry::list_entries(&conn, None, false, false, 2, 2).unwrap();
    assert_eq!(page2.len(), 2);
    assert_eq!(page2[0].title, "e2");
    assert_eq!(page2[1].title, "e1");

    // last page has the remainder.
    let page3 = entry::list_entries(&conn, None, false, false, 2, 4).unwrap();
    assert_eq!(page3.len(), 1);
    assert_eq!(page3[0].title, "e0");

    // offset past the end is empty.
    assert!(entry::list_entries(&conn, None, false, false, 2, 6).unwrap().is_empty());
}

#[test]
fn toggle_entry_star_returns_new_state() {
    let conn = test_db();
    feed::upsert_feed(&conn, &sample_feed("f1", "https://a/feed")).unwrap();
    entry::upsert_entries(&conn, "f1", &[draft("a", "https://a/1")]).unwrap();
    let id = entry::list_entries(&conn, None, false, false, 50, 0).unwrap()[0].id.clone();

    // Fresh entries are un-starred; toggling flips to starred.
    let now_starred = entry::toggle_entry_star(&conn, &id).unwrap();
    assert!(now_starred);
    assert!(entry::get_entry_by_id(&conn, &id).unwrap().is_starred);

    // Toggling again flips back to un-starred.
    let now_unstarred = entry::toggle_entry_star(&conn, &id).unwrap();
    assert!(!now_unstarred);
    assert!(!entry::get_entry_by_id(&conn, &id).unwrap().is_starred);
}

#[test]
fn toggle_entry_star_missing_is_not_found() {
    let conn = test_db();
    feed::upsert_feed(&conn, &sample_feed("f1", "https://a/feed")).unwrap();
    match entry::toggle_entry_star(&conn, "missing") {
        Err(AppError::NotFound { resource, .. }) => assert_eq!(resource, "entry"),
        other => panic!("expected NotFound, got {other:?}"),
    }
}

#[test]
fn adjacent_entries_walks_newest_first_list() {
    let conn = test_db();
    feed::upsert_feed(&conn, &sample_feed("f1", "https://a/feed")).unwrap();
    // Three entries with distinct, increasing publish times.
    entry::upsert_entries(
        &conn,
        "f1",
        &[
            draft_at("oldest", "https://a/1", 1_000_000),
            draft_at("middle", "https://a/2", 2_000_000),
            draft_at("newest", "https://a/3", 3_000_000),
        ],
    )
    .unwrap();

    // newest-first order: newest, middle, oldest.
    let items = entry::list_entries(&conn, None, false, false, 50, 0).unwrap();
    assert_eq!(
        items.iter().map(|i| i.title.clone()).collect::<Vec<_>>(),
        vec!["newest", "middle", "oldest"]
    );

    let newest_id = items[0].id.clone();
    let middle_id = items[1].id.clone();
    let oldest_id = items[2].id.clone();

    // newest: no prev (nothing newer), next is middle.
    let adj = entry::get_adjacent_entries(&conn, &newest_id, None, false, false).unwrap();
    assert_eq!(adj.prev, None);
    assert_eq!(adj.next.as_deref(), Some(middle_id.as_str()));

    // middle: prev is newest, next is oldest.
    let adj = entry::get_adjacent_entries(&conn, &middle_id, None, false, false).unwrap();
    assert_eq!(adj.prev.as_deref(), Some(newest_id.as_str()));
    assert_eq!(adj.next.as_deref(), Some(oldest_id.as_str()));

    // oldest: prev is middle, no next (nothing older).
    let adj = entry::get_adjacent_entries(&conn, &oldest_id, None, false, false).unwrap();
    assert_eq!(adj.prev.as_deref(), Some(middle_id.as_str()));
    assert_eq!(adj.next, None);
}

#[test]
fn adjacent_entries_respects_unread_filter() {
    let conn = test_db();
    feed::upsert_feed(&conn, &sample_feed("f1", "https://a/feed")).unwrap();
    entry::upsert_entries(
        &conn,
        "f1",
        &[
            draft_at("oldest", "https://a/1", 1_000_000),
            draft_at("middle", "https://a/2", 2_000_000),
            draft_at("newest", "https://a/3", 3_000_000),
        ],
    )
    .unwrap();
    let items = entry::list_entries(&conn, None, false, false, 50, 0).unwrap();
    let middle_id = items[1].id.clone();
    let newest_id = items[0].id.clone();

    // Mark the middle entry read. Under the unread filter, its neighbours skip
    // over the read middle entry: newest's next becomes oldest, not middle.
    entry::mark_entry_read(&conn, &middle_id, true).unwrap();
    let oldest_id = items[2].id.clone();

    let adj = entry::get_adjacent_entries(&conn, &newest_id, None, true, false).unwrap();
    assert_eq!(adj.next.as_deref(), Some(oldest_id.as_str()));

    // The read middle entry still positions between the unread newest/oldest:
    // navigation finds the nearest unread entries on either side.
    let adj = entry::get_adjacent_entries(&conn, &middle_id, None, true, false).unwrap();
    assert_eq!(adj.prev.as_deref(), Some(newest_id.as_str()));
    assert_eq!(adj.next.as_deref(), Some(oldest_id.as_str()));
}

#[test]
fn adjacent_entries_unknown_id_returns_none() {
    let conn = test_db();
    feed::upsert_feed(&conn, &sample_feed("f1", "https://a/feed")).unwrap();
    let adj = entry::get_adjacent_entries(&conn, "missing", None, false, false).unwrap();
    assert_eq!(adj.prev, None);
    assert_eq!(adj.next, None);
}

#[test]
fn entry_fk_constraint_rejects_orphan_feed_id() {
    let conn = test_db();
    let err = entry::upsert_entries(&conn, "no-such-feed", &[draft("a", "https://a/1")])
        .unwrap_err();
    assert!(matches!(err, AppError::Database(_)), "got {err:?}");
}

#[test]
fn mark_all_read_updates_counts() {
    let conn = test_db();
    feed::upsert_feed(&conn, &sample_feed("f1", "https://a/feed")).unwrap();
    feed::upsert_feed(&conn, &sample_feed("f2", "https://b/feed")).unwrap();
    entry::upsert_entries(&conn, "f1", &[draft("a", "https://a/1")]).unwrap();
    entry::upsert_entries(&conn, "f2", &[draft("b", "https://b/1")]).unwrap();

    // Scope to f1 only.
    entry::mark_all_read(&conn, Some("f1")).unwrap();
    let f1 = feed::get_feed_by_id(&conn, "f1").unwrap().unwrap();
    assert_eq!(f1.unread_count, 0);
    let f2 = feed::get_feed_by_id(&conn, "f2").unwrap().unwrap();
    assert_eq!(f2.unread_count, 1);

    // Mark everything read.
    entry::mark_all_read(&conn, None).unwrap();
    let f2 = feed::get_feed_by_id(&conn, "f2").unwrap().unwrap();
    assert_eq!(f2.unread_count, 0);
}

#[test]
fn category_crud_roundtrip() {
    let conn = test_db();
    use crate::api::types::Category;
    category::upsert_category(&conn, &Category { id: "c1".to_owned(), title: "News".to_owned() })
        .unwrap();
    category::upsert_category(&conn, &Category { id: "c2".to_owned(), title: "Tech".to_owned() })
        .unwrap();

    let listed = category::list_categories(&conn).unwrap();
    assert_eq!(listed.len(), 2);
    // Ordered by title (News before Tech).
    assert_eq!(listed[0].id, "c1");

    // Update via upsert.
    category::upsert_category(&conn, &Category { id: "c1".to_owned(), title: "World".to_owned() })
        .unwrap();
    let fetched = category::list_categories(&conn).unwrap();
    let c1 = fetched.iter().find(|c| c.id == "c1").unwrap();
    assert_eq!(c1.title, "World");

    category::delete_category(&conn, "c1").unwrap();
    assert_eq!(category::list_categories(&conn).unwrap().len(), 1);
}

#[test]
fn migrations_are_idempotent() {
    // Running migrations twice (e.g. on a rerun) must not error.
    let mut conn = Connection::open_in_memory().unwrap();
    crate::db::migrations::run(&mut conn).unwrap();
    crate::db::migrations::run(&mut conn).unwrap();
}

#[test]
fn search_entries_finds_by_title_summary_and_content() {
    let conn = test_db();
    feed::upsert_feed(&conn, &sample_feed("f1", "https://a/feed")).unwrap();
    entry::upsert_entries(
        &conn,
        "f1",
        &[
            EntryDraft {
                title: "Rust Programming".to_owned(),
                url: "https://a/1".to_owned(),
                author: None,
                summary: Some("A summary about coding".to_owned()),
                content: Some("Full body text here".to_owned()),
                published_at: Some(Utc::now()),
            },
            EntryDraft {
                title: "Unrelated".to_owned(),
                url: "https://a/2".to_owned(),
                author: None,
                summary: Some("Nothing relevant".to_owned()),
                content: Some("No keywords here".to_owned()),
                published_at: Some(Utc::now()),
            },
            EntryDraft {
                title: "Another Post".to_owned(),
                url: "https://a/3".to_owned(),
                author: None,
                summary: Some("Mentions Rust briefly".to_owned()),
                content: Some("Some content".to_owned()),
                published_at: Some(Utc::now()),
            },
        ],
    )
    .unwrap();

    // Match by title.
    let results = entry::search_entries(&conn, "Rust", None, 50).unwrap();
    assert_eq!(results.len(), 2);

    // Match by summary ("coding").
    let results = entry::search_entries(&conn, "coding", None, 50).unwrap();
    assert_eq!(results.len(), 1);
    assert_eq!(results[0].title, "Rust Programming");

    // Match by content ("body").
    let results = entry::search_entries(&conn, "body", None, 50).unwrap();
    assert_eq!(results.len(), 1);
    assert_eq!(results[0].title, "Rust Programming");
}

#[test]
fn search_entries_is_case_insensitive() {
    let conn = test_db();
    feed::upsert_feed(&conn, &sample_feed("f1", "https://a/feed")).unwrap();
    entry::upsert_entries(
        &conn,
        "f1",
        &[draft("Flutter Development Guide", "https://a/1")],
    )
    .unwrap();

    let upper = entry::search_entries(&conn, "FLUTTER", None, 50).unwrap();
    assert_eq!(upper.len(), 1);
    let lower = entry::search_entries(&conn, "flutter", None, 50).unwrap();
    assert_eq!(lower.len(), 1);
    let mixed = entry::search_entries(&conn, "fLuTtEr", None, 50).unwrap();
    assert_eq!(mixed.len(), 1);
}

#[test]
fn search_entries_scopes_to_feed() {
    let conn = test_db();
    feed::upsert_feed(&conn, &sample_feed("f1", "https://a/feed")).unwrap();
    feed::upsert_feed(&conn, &sample_feed("f2", "https://b/feed")).unwrap();
    entry::upsert_entries(&conn, "f1", &[draft("Shared keyword", "https://a/1")]).unwrap();
    entry::upsert_entries(&conn, "f2", &[draft("Shared keyword too", "https://b/1")]).unwrap();

    // All feeds: both match.
    let all = entry::search_entries(&conn, "Shared", None, 50).unwrap();
    assert_eq!(all.len(), 2);

    // Scoped to f1: only one.
    let scoped = entry::search_entries(&conn, "Shared", Some("f1"), 50).unwrap();
    assert_eq!(scoped.len(), 1);
    assert_eq!(scoped[0].feed_id, "f1");
}

#[test]
fn search_entries_empty_query_returns_empty() {
    let conn = test_db();
    feed::upsert_feed(&conn, &sample_feed("f1", "https://a/feed")).unwrap();
    entry::upsert_entries(&conn, "f1", &[draft("Some title", "https://a/1")]).unwrap();

    assert!(entry::search_entries(&conn, "", None, 50).unwrap().is_empty());
    assert!(entry::search_entries(&conn, "   ", None, 50).unwrap().is_empty());
}

#[test]
fn search_entries_respects_limit() {
    let conn = test_db();
    feed::upsert_feed(&conn, &sample_feed("f1", "https://a/feed")).unwrap();
    let drafts: Vec<EntryDraft> = (0..5)
        .map(|i| draft_at(&format!("keyword-{i}"), &format!("https://a/{i}"), 1_000_000 + i))
        .collect();
    entry::upsert_entries(&conn, "f1", &drafts).unwrap();

    let results = entry::search_entries(&conn, "keyword", None, 3).unwrap();
    assert_eq!(results.len(), 3);
    // newest-first: keyword-4, keyword-3, keyword-2
    assert_eq!(results[0].title, "keyword-4");
    assert_eq!(results[1].title, "keyword-3");
    assert_eq!(results[2].title, "keyword-2");
}

#[test]
fn search_entries_no_match_returns_empty() {
    let conn = test_db();
    feed::upsert_feed(&conn, &sample_feed("f1", "https://a/feed")).unwrap();
    entry::upsert_entries(&conn, "f1", &[draft("Hello World", "https://a/1")]).unwrap();

    assert!(entry::search_entries(&conn, "nonexistent", None, 50).unwrap().is_empty());
}

#[test]
fn init_db_then_with_db_round_trips() {
    // Exercises the real init path (file-based DB, WAL/FK pragmas, migrations)
    // and the global `with_db` borrow — the path Dart hits via `initDatabase`.
    // Uses a process-unique temp path; the OnceLock is process-global, so this
    // is the only test that touches `init_db`/`with_db`.
    use crate::db::connection::{init_db, with_db};

    let path = std::env::temp_dir()
        .join(format!("rss_reader_p0b_test_{}.db", std::process::id()));
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(path.with_extension("db-wal"));
    let _ = std::fs::remove_file(path.with_extension("db-shm"));

    init_db(path.to_str().unwrap()).unwrap();

    let feed = sample_feed("f1", "https://example.com/feed.xml");
    with_db(|conn| feed::upsert_feed(conn, &feed)).unwrap();
    with_db(|conn| {
        entry::upsert_entries(conn, "f1", &[draft("a", "https://example.com/1")])
    })
    .unwrap();

    let listed =
        with_db(|conn| entry::list_entries(conn, None, false, false, 50, 0)).unwrap();
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0].feed_title, "Feed f1");

    // init_db is once-only; a second call errors.
    let dup = init_db(path.to_str().unwrap());
    assert!(dup.is_err());

    // Best-effort cleanup (the connection stays open in the global, but on
    // Linux unlinking an open file succeeds).
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(path.with_extension("db-wal"));
    let _ = std::fs::remove_file(path.with_extension("db-shm"));
}
