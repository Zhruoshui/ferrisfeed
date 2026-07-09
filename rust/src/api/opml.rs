//! OPML 2.0 import/export exposed over flutter_rust_bridge.
//!
//! Import parses an OPML document and batch-subscribes to each `<outline
//! xmlUrl=...>` entry, reusing [`crate::feed::subscribe_feed_impl`] (idempotent
//! on `source_url`). Folder/category nesting from parent group outlines is
//! applied to the persisted feed's `folder`/`category` columns. Per-feed
//! failures are isolated: one bad URL does not abort the rest.
//!
//! Export serializes the current feed list into an OPML 2.0 `<outline>` tree,
//! grouping feeds by `folder` into nested outlines.
//!
//! The `opml` crate (pure-Rust, `hard-xml` based - no C deps) handles spec
//! compliance. Its types stay internal to this module; only `ImportReport`,
//! `String`, and `AppError` cross the FRB boundary.

use crate::api::error::AppError;
use crate::api::types::{Feed, ImportReport};
use crate::db::connection::with_db;
use crate::db::repositories;
use crate::feed;

use opml::{Body, Head, OPML, Outline};

/// A feed entry extracted from an OPML outline (internal, not FRB-exposed).
struct OpmlFeedEntry {
    url: String,
    #[allow(dead_code)]
    title: Option<String>,
    #[allow(dead_code)]
    html_url: Option<String>,
    folder: Option<String>,
    category: Option<String>,
}

// ---------------------------------------------------------------------------
// FRB-exposed functions
// ---------------------------------------------------------------------------

/// Imports an OPML 2.0 document: parses each `<outline xmlUrl=...>`, subscribes
/// to the feed (fetch + parse + persist), and applies folder/category nesting.
///
/// Per-feed failures are isolated and reported in [`ImportReport::failed_urls`].
/// Already-subscribed feeds (matched by `source_url`) are skipped without a
/// network round-trip - only their folder/category is updated.
///
/// This is an `async fn` because each new subscription performs an HTTP fetch
/// via [`feed::subscribe_feed_impl`]. FRB v2.12 hosts a tokio runtime, so the
/// awaits work directly (see `directory-structure.md` gotcha).
#[flutter_rust_bridge::frb]
pub async fn import_opml(xml: String) -> Result<ImportReport, AppError> {
    let opml = parse_opml(&xml)?;
    let entries = collect_opml_feeds(&opml);

    let total = entries.len() as i32;
    let mut imported = 0;
    let mut skipped = 0;
    let mut failed = 0;
    let mut failed_urls = Vec::new();

    for entry in &entries {
        // Pre-check: if already subscribed, skip the HTTP fetch and just apply
        // the folder/category from the OPML. This makes re-imports fast.
        let existing = with_db(|conn| {
            repositories::feed::get_feed_by_source_url(conn, &entry.url)
        })?;
        if let Some(feed) = existing {
            apply_folder(&feed.id, entry);
            skipped += 1;
            continue;
        }

        // New subscription: fetch + parse + persist.
        match feed::subscribe_feed_impl(&entry.url).await {
            Ok(feed) => {
                apply_folder(&feed.id, entry);
                imported += 1;
            }
            Err(_) => {
                failed += 1;
                failed_urls.push(entry.url.clone());
            }
        }
    }

    Ok(ImportReport {
        total,
        imported,
        failed,
        skipped,
        failed_urls,
    })
}

/// Exports the current feed list to an OPML 2.0 XML string. Feeds are grouped
/// by `folder` into nested `<outline>` elements.
///
/// This is a plain `pub fn` (runs on the FRB worker pool): it only reads the
/// database and serializes XML, with no network I/O.
#[flutter_rust_bridge::frb]
pub fn export_opml() -> Result<String, AppError> {
    let feeds = with_db(|conn| repositories::feed::list_feeds(conn))?;
    let opml = build_opml_from_feeds(&feeds);
    opml.to_string().map_err(|e| AppError::Io(e.to_string()))
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Parses an OPML string, mapping `opml::Error` to `AppError`.
fn parse_opml(xml: &str) -> Result<OPML, AppError> {
    OPML::from_str(xml).map_err(|e| match e {
        opml::Error::BodyHasNoOutlines => {
            AppError::invalid_input("OPML body has no <outline> elements")
        }
        opml::Error::UnsupportedVersion(v) => {
            AppError::invalid_input(format!("unsupported OPML version: {v}"))
        }
        opml::Error::XmlError(_) => AppError::FeedParse {
            url: "opml".to_string(),
            message: e.to_string(),
        },
        opml::Error::IoError(io) => AppError::Io(io.to_string()),
    })
}

/// Returns `Some(s)` if `s` is non-empty, `None` otherwise.
fn non_empty(s: String) -> Option<String> {
    if s.is_empty() { None } else { Some(s) }
}

/// Recursively walks the OPML outline tree, collecting every `<outline
/// xmlUrl=...>` as a feed entry. Parent outlines without `xmlUrl` are treated
/// as folders; their `text`/`title` becomes the feed's `folder`. URLs are
/// deduplicated (first occurrence wins).
fn collect_opml_feeds(opml: &OPML) -> Vec<OpmlFeedEntry> {
    let mut entries = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for outline in &opml.body.outlines {
        collect_outlines(outline, None, &mut entries, &mut seen);
    }
    entries
}

fn collect_outlines(
    outline: &Outline,
    folder: Option<&str>,
    entries: &mut Vec<OpmlFeedEntry>,
    seen: &mut std::collections::HashSet<String>,
) {
    if let Some(url) = &outline.xml_url {
        if !url.is_empty() && seen.insert(url.clone()) {
            let folder_name = folder.map(|s| s.to_string());
            let category = outline
                .category
                .clone()
                .filter(|s| !s.is_empty());
            let title = outline
                .title
                .clone()
                .filter(|s| !s.is_empty())
                .or_else(|| non_empty(outline.text.clone()));
            let html_url = outline
                .html_url
                .clone()
                .filter(|s| !s.is_empty());
            entries.push(OpmlFeedEntry {
                url: url.clone(),
                title,
                html_url,
                folder: folder_name,
                category,
            });
        }
        return;
    }

    // No xmlUrl -> this is a folder/group outline. Its text/title is the
    // folder name. Recurse into children.
    let folder_name = outline
        .title
        .clone()
        .filter(|s| !s.is_empty())
        .or_else(|| non_empty(outline.text.clone()));
    for child in &outline.outlines {
        collect_outlines(child, folder_name.as_deref(), entries, seen);
    }
}

/// Builds an OPML 2.0 document from a feed list, grouping by `folder`.
fn build_opml_from_feeds(feeds: &[Feed]) -> OPML {
    let mut opml = OPML {
        version: "2.0".to_string(),
        head: Some(Head {
            title: Some("RSS Reader Subscriptions".to_string()),
            date_created: Some(rfc822_now()),
            ..Head::default()
        }),
        body: Body {
            outlines: Vec::new(),
        },
    };

    // Preserve feed order (already sorted by title from list_feeds). Group
    // feeds by folder, keeping first-seen order of folders.
    let mut folder_groups: Vec<(String, Vec<&Feed>)> = Vec::new();
    let mut top_level: Vec<&Feed> = Vec::new();

    for feed in feeds {
        match feed.folder.as_ref().filter(|f| !f.is_empty()) {
            Some(folder) => {
                if let Some((_, group)) =
                    folder_groups.iter_mut().find(|(f, _)| f == folder)
                {
                    group.push(feed);
                } else {
                    folder_groups.push((folder.clone(), vec![feed]));
                }
            }
            None => top_level.push(feed),
        }
    }

    for (folder, group_feeds) in folder_groups {
        let mut group = Outline {
            text: folder.clone(),
            title: Some(folder),
            ..Outline::default()
        };
        for feed in group_feeds {
            group.outlines.push(feed_to_outline(feed));
        }
        opml.body.outlines.push(group);
    }

    for feed in top_level {
        opml.body.outlines.push(feed_to_outline(feed));
    }

    opml
}

fn feed_to_outline(feed: &Feed) -> Outline {
    Outline {
        text: feed.title.clone(),
        title: Some(feed.title.clone()),
        r#type: Some("rss".to_string()),
        xml_url: Some(feed.source_url.clone()),
        html_url: feed.site_url.clone(),
        // Preserve the category so it survives an export -> re-import
        // round-trip (import reads `outline.category`).
        category: feed.category.clone(),
        ..Outline::default()
    }
}

/// Updates a feed's folder/category from an OPML entry. Best-effort: a DB error
/// here is discarded (there is no logging infrastructure yet) and does not abort
/// the import - the feed was already subscribed successfully, so a folder
/// assignment failure should not undo that.
fn apply_folder(feed_id: &str, entry: &OpmlFeedEntry) {
    if entry.folder.is_none() && entry.category.is_none() {
        return;
    }
    let _ = with_db(|conn| {
        repositories::feed::set_feed_folder(
            conn,
            feed_id,
            entry.folder.as_deref(),
            entry.category.as_deref(),
        )
    });
}

/// Returns the current time as an RFC 822 date string (the OPML spec's
/// `dateCreated` format).
fn rfc822_now() -> String {
    use chrono::Utc;
    // chrono's DateTime::to_rfc2822 produces RFC 2822, which is a superset of
    // RFC 822 and is what OPML readers expect.
    Utc::now().to_rfc2822()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::types::ArticleViewMode;
    use chrono::Utc;

    const SAMPLE_OPML: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <head>
    <title>My Subscriptions</title>
  </head>
  <body>
    <outline text="News" title="News">
      <outline text="BBC News" title="BBC News" type="rss" xmlUrl="https://feeds.bbci.co.uk/news/rss.xml" htmlUrl="https://bbc.co.uk/news" />
      <outline text="Reuters" title="Reuters" type="rss" xmlUrl="https://feeds.reuters.com/reuters/topNews" htmlUrl="https://reuters.com" />
    </outline>
    <outline text="Tech Blog" title="Tech Blog" type="rss" xmlUrl="https://example.com/tech/feed.xml" htmlUrl="https://example.com/tech" />
  </body>
</opml>"#;

    fn sample_feed(id: &str, url: &str, folder: Option<&str>) -> Feed {
        Feed {
            id: id.to_owned(),
            title: format!("Feed {id}"),
            source_url: url.to_owned(),
            site_url: Some(format!("https://example.com/{id}")),
            description: None,
            image_url: None,
            folder: folder.map(|s| s.to_owned()),
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

    #[test]
    fn collect_extracts_feeds_with_folders() {
        let opml = parse_opml(SAMPLE_OPML).unwrap();
        let entries = collect_opml_feeds(&opml);

        // Three feeds total: two under "News", one at top level.
        assert_eq!(entries.len(), 3);

        // The two News feeds have folder = "News".
        let news_feeds: Vec<_> = entries.iter().filter(|e| e.folder.as_deref() == Some("News")).collect();
        assert_eq!(news_feeds.len(), 2);

        // The top-level feed has no folder.
        let top_feeds: Vec<_> = entries.iter().filter(|e| e.folder.is_none()).collect();
        assert_eq!(top_feeds.len(), 1);
        assert_eq!(top_feeds[0].url, "https://example.com/tech/feed.xml");
    }

    #[test]
    fn collect_deduplicates_by_url() {
        let xml = r#"<opml version="2.0"><head/><body>
          <outline text="A" xmlUrl="https://example.com/feed.xml" />
          <outline text="Group">
            <outline text="B" xmlUrl="https://example.com/feed.xml" />
          </outline>
        </body></opml>"#;
        let opml = parse_opml(xml).unwrap();
        let entries = collect_opml_feeds(&opml);

        // The same URL appears twice; only the first occurrence is kept.
        assert_eq!(entries.len(), 1);
        // First occurrence has no folder (top-level), so folder is None.
        assert!(entries[0].folder.is_none());
    }

    #[test]
    fn collect_handles_deep_nesting() {
        let xml = r#"<opml version="2.0"><head/><body>
          <outline text="Level1">
            <outline text="Level2">
              <outline text="Deep Feed" xmlUrl="https://deep.example.com/feed" />
            </outline>
          </outline>
        </body></opml>"#;
        let opml = parse_opml(xml).unwrap();
        let entries = collect_opml_feeds(&opml);

        assert_eq!(entries.len(), 1);
        // The immediate parent folder is "Level2".
        assert_eq!(entries[0].folder.as_deref(), Some("Level2"));
    }

    #[test]
    fn export_groups_by_folder() {
        let feeds = vec![
            sample_feed("f1", "https://a.com/feed", Some("News")),
            sample_feed("f2", "https://b.com/feed", Some("News")),
            sample_feed("f3", "https://c.com/feed", None),
        ];
        let opml = build_opml_from_feeds(&feeds);
        let xml = opml.to_string().unwrap();

        // The exported XML must be re-parseable.
        let reparsed = parse_opml(&xml).unwrap();
        let entries = collect_opml_feeds(&reparsed);

        // Three feeds survive the round-trip.
        assert_eq!(entries.len(), 3);

        // Two feeds under "News", one at top level.
        let news = entries.iter().filter(|e| e.folder.as_deref() == Some("News")).count();
        assert_eq!(news, 2);
        let top = entries.iter().filter(|e| e.folder.is_none()).count();
        assert_eq!(top, 1);
    }

    #[test]
    fn export_then_import_round_trip_preserves_urls_and_folders() {
        // Build a set of feeds, export to OPML, re-parse, and verify the
        // extracted entries match the originals.
        let feeds = vec![
            sample_feed("f1", "https://news.example.com/rss", Some("News")),
            sample_feed("f2", "https://tech.example.com/feed", Some("Tech")),
            sample_feed("f3", "https://blog.example.com/atom", None),
        ];

        let opml = build_opml_from_feeds(&feeds);
        let xml = opml.to_string().unwrap();

        // Re-parse the exported XML.
        let reparsed = parse_opml(&xml).unwrap();
        let entries = collect_opml_feeds(&reparsed);

        // Every original URL is present.
        let urls: Vec<_> = entries.iter().map(|e| e.url.as_str()).collect();
        assert!(urls.contains(&"https://news.example.com/rss"));
        assert!(urls.contains(&"https://tech.example.com/feed"));
        assert!(urls.contains(&"https://blog.example.com/atom"));

        // Folders are preserved.
        let news = entries.iter().find(|e| e.url == "https://news.example.com/rss").unwrap();
        assert_eq!(news.folder.as_deref(), Some("News"));
        let tech = entries.iter().find(|e| e.url == "https://tech.example.com/feed").unwrap();
        assert_eq!(tech.folder.as_deref(), Some("Tech"));
        let blog = entries.iter().find(|e| e.url == "https://blog.example.com/atom").unwrap();
        assert!(blog.folder.is_none());
    }

    #[test]
    fn export_preserves_category_round_trip() {
        // A feed with a `category` but no `folder` must keep its category
        // through an export -> re-import round-trip (the category is written as
        // the OPML `category` attribute on the leaf outline).
        let mut feed = sample_feed("f1", "https://tagged.example.com/feed", None);
        feed.category = Some("Tech".to_string());

        let opml = build_opml_from_feeds(&[feed]);
        let xml = opml.to_string().unwrap();

        let reparsed = parse_opml(&xml).unwrap();
        let entries = collect_opml_feeds(&reparsed);
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].url, "https://tagged.example.com/feed");
        assert_eq!(entries[0].category.as_deref(), Some("Tech"));
        // No folder was set, so the feed is exported at the top level.
        assert!(entries[0].folder.is_none());
    }

    #[test]
    fn parse_rejects_empty_body() {
        let xml = r#"<opml version="2.0"><head/><body/></opml>"#;
        let result = parse_opml(xml);
        assert!(result.is_err());
    }

    #[test]
    fn parse_rejects_malformed_xml() {
        let xml = "<not valid xml<<<";
        let result = parse_opml(xml);
        assert!(result.is_err());
    }

    #[test]
    fn parse_rejects_unsupported_version() {
        let xml = r#"<opml version="3.0"><head/><body><outline text="x"/></body></opml>"#;
        let result = parse_opml(xml);
        assert!(result.is_err());
    }

    // --- End-to-end network smoke test (ignored; run with --ignored) ---------

    #[tokio::test]
    #[ignore = "requires network; run with --ignored"]
    async fn import_real_opml_end_to_end() {
        use crate::db::connection::{init_db, with_db};

        let path = std::env::temp_dir()
            .join(format!("rss_reader_p3a_smoke_{}.db", std::process::id()));
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(path.with_extension("db-wal"));
        let _ = std::fs::remove_file(path.with_extension("db-shm"));
        let _ = init_db(path.to_str().unwrap());

        let xml = r#"<opml version="2.0"><head/><body>
          <outline text="News">
            <outline text="BBC" type="rss" xmlUrl="https://feeds.bbci.co.uk/news/rss.xml" />
          </outline>
        </body></opml>"#;

        let report = import_opml(xml.to_string()).await.unwrap();
        assert_eq!(report.total, 1);
        assert_eq!(report.imported, 1);
        assert_eq!(report.failed, 0);

        // The feed was persisted with the folder set.
        let feed = with_db(|conn| {
            repositories::feed::get_feed_by_source_url(
                conn,
                "https://feeds.bbci.co.uk/news/rss.xml",
            )
        })
        .unwrap()
        .unwrap();
        assert_eq!(feed.folder.as_deref(), Some("News"));

        // Re-import: the feed is now skipped (idempotent).
        let report2 = import_opml(xml.to_string()).await.unwrap();
        assert_eq!(report2.total, 1);
        assert_eq!(report2.imported, 0);
        assert_eq!(report2.skipped, 1);
        assert_eq!(report2.failed, 0);
    }
}
