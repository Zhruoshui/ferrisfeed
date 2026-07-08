//! Feed parsing via `feed-rs` -> internal `ParsedFeed`/`ParsedEntry`.
//!
//! `feed-rs::parser::parse` auto-detects RSS2/Atom/RSS1/JSON-Feed and
//! normalizes format-specific fields into a single model. This module maps that
//! model to the internal structs used by the subscribe/discover flows:
//!
//! - `content:encoded` -> `ParsedEntry.content`
//! - `media:*` / enclosure -> `ParsedEntry.media`
//! - dates -> `chrono::DateTime<Utc>` (already parsed by feed-rs)
//! - relative URLs -> resolved against `base_url` via the `url` crate
//!
//! Parse failures map to [`AppError::FeedParse`].

use chrono::{DateTime, Utc};
use serde::Serialize;
use url::Url;

use crate::api::AppError;

/// Normalized feed metadata + parsed entries.
///
/// `subscribe_feed` (P1a) only persists feed-level fields; the entries are
/// parsed so P1b sync can consume them without re-fetching.
#[allow(dead_code)] // entries + most entry fields are consumed by P1b sync, not P1a subscribe
pub(crate) struct ParsedFeed {
    pub title: String,
    pub site_url: Option<String>,
    pub description: Option<String>,
    pub entries: Vec<ParsedEntry>,
}

#[allow(dead_code)] // consumed by P1b entry sync
pub(crate) struct ParsedEntry {
    pub title: String,
    pub url: String,
    /// The feed entry's stable id (`<guid>` for RSS, `<id>` for Atom, JSON Feed
    /// `id`). Used as the idempotent upsert key (falling back to `url` when
    /// empty). Carried through to the `entries.guid` column by P1b sync.
    pub guid: Option<String>,
    pub author: Option<String>,
    pub summary: Option<String>,
    pub content: Option<String>,
    pub published_at: Option<DateTime<Utc>>,
    pub media: Vec<MediaItem>,
}

#[allow(dead_code)] // consumed by P1b entry sync
#[derive(Debug, Clone, Serialize)]
pub(crate) struct MediaItem {
    pub url: String,
    pub mime_type: Option<String>,
    pub kind: Option<String>,
}

/// Parses feed bytes (RSS2/Atom/RSS1/JSON-Feed) into a normalized `ParsedFeed`.
///
/// `base_url` is the feed URL, used to resolve any residual relative links that
/// feed-rs did not already resolve via `xml:base`.
pub(crate) fn parse_feed(bytes: &[u8], base_url: &str) -> Result<ParsedFeed, AppError> {
    let feed = feed_rs::parser::parse(bytes).map_err(|e| AppError::FeedParse {
        url: base_url.to_string(),
        message: e.to_string(),
    })?;
    Ok(map_feed(feed, base_url))
}

fn map_feed(feed: feed_rs::model::Feed, base_url: &str) -> ParsedFeed {
    let title = feed
        .title
        .map(|t| t.content)
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| base_url.to_string());

    // The site URL is the alternate link (Atom) or the channel link (RSS).
    let site_url = feed
        .links
        .iter()
        .find(|l| l.rel.as_deref().map(|r| r == "alternate").unwrap_or(true))
        .map(|l| resolve_url(&l.href, base_url));

    let description = feed.description.map(|t| t.content);

    let entries = feed
        .entries
        .into_iter()
        .map(|e| map_entry(e, base_url))
        .collect();

    ParsedFeed {
        title,
        site_url,
        description,
        entries,
    }
}

fn map_entry(e: feed_rs::model::Entry, base_url: &str) -> ParsedEntry {
    let title = e
        .title
        .map(|t| t.content)
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| "Untitled".to_string());

    let url = e
        .links
        .iter()
        .find(|l| l.rel.as_deref().map(|r| r == "alternate").unwrap_or(true))
        .map(|l| resolve_url(&l.href, base_url))
        .unwrap_or_default();

    // The entry id is the feed's stable identifier for the item (RSS <guid>,
    // Atom <id>, JSON Feed id). Trimmed; empty values become `None` so the
    // sync upsert falls back to the URL as the dedup key.
    let guid = {
        let trimmed = e.id.trim();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed.to_string())
        }
    };

    let author = e.authors.first().map(|p| p.name.clone());

    // content:encoded -> content; summary falls back to content, content to summary.
    let content_body = e.content.as_ref().and_then(|c| c.body.clone());
    let summary_text = e.summary.map(|t| t.content);
    let content = content_body.clone().or_else(|| summary_text.clone());
    let summary = summary_text.or(content_body);

    let published_at = e.published.or(e.updated);

    let media = extract_media(&e.media, base_url);

    ParsedEntry {
        title,
        url,
        guid,
        author,
        summary,
        content,
        published_at,
        media,
    }
}

/// Extracts media items from `media:content` / `media:group` / `media:thumbnail`
/// (feed-rs already normalizes enclosures into `MediaObject`).
fn extract_media(media_objs: &[feed_rs::model::MediaObject], base_url: &str) -> Vec<MediaItem> {
    let mut items = Vec::new();
    for obj in media_objs {
        for c in &obj.content {
            if let Some(u) = &c.url {
                items.push(MediaItem {
                    url: resolve_url(u.as_ref(), base_url),
                    mime_type: c.content_type.as_ref().map(|t| t.to_string()),
                    kind: None,
                });
            }
        }
        for t in &obj.thumbnails {
            items.push(MediaItem {
                url: resolve_url(&t.image.uri, base_url),
                mime_type: None,
                kind: Some("thumbnail".to_string()),
            });
        }
    }
    items
}

/// Resolves a possibly-relative `href` against `base_url`. Returns the original
/// string unchanged if `base_url` is not a valid absolute URL or `href` cannot
/// be joined (feed-rs usually resolves via `xml:base` already, so this is a
/// safety net for residual relative URLs).
fn resolve_url(href: &str, base_url: &str) -> String {
    if href.is_empty() {
        return String::new();
    }
    if let Ok(base) = Url::parse(base_url) {
        if let Ok(abs) = base.join(href) {
            return abs.to_string();
        }
    }
    href.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE_RSS: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:media="http://search.yahoo.com/mrss/">
  <channel>
    <title>Example Feed</title>
    <link>https://example.com</link>
    <description>Example stories</description>
    <item>
      <title>First story</title>
      <link>https://example.com/articles/1</link>
      <description>Hello from the feed</description>
      <content:encoded><![CDATA[<p>Full HTML content</p>]]></content:encoded>
      <pubDate>Wed, 17 Jun 2026 10:00:00 GMT</pubDate>
      <media:content url="https://example.com/img/1.jpg" medium="image" />
    </item>
    <item>
      <title>Second story</title>
      <link>https://example.com/articles/2</link>
      <description>Second article</description>
      <pubDate>Wed, 17 Jun 2026 11:00:00 GMT</pubDate>
    </item>
  </channel>
</rss>"#;

    const SAMPLE_ATOM: &str = r#"<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Atom Example</title>
  <link href="https://example.org/"/>
  <link rel="self" href="https://example.org/feed.atom"/>
  <subtitle>An atom feed</subtitle>
  <entry>
    <title>Atom entry one</title>
    <link href="https://example.org/entries/1"/>
    <id>urn:uuid:1</id>
    <updated>2026-06-17T10:00:00Z</updated>
    <published>2026-06-17T09:00:00Z</published>
    <author><name>Jane Doe</name></author>
    <summary>A short summary</summary>
    <content type="html">&lt;p&gt;Full content&lt;/p&gt;</content>
  </entry>
</feed>"#;

    #[test]
    fn parses_rss_feed_metadata() {
        let parsed = parse_feed(SAMPLE_RSS.as_bytes(), "https://example.com/feed.xml").unwrap();
        assert_eq!(parsed.title, "Example Feed");
        // feed-rs/url normalizes the bare host link to add a trailing slash.
        assert_eq!(parsed.site_url.as_deref(), Some("https://example.com/"));
        assert_eq!(parsed.description.as_deref(), Some("Example stories"));
        assert_eq!(parsed.entries.len(), 2);
    }

    #[test]
    fn parses_rss_content_encoded_and_media() {
        let parsed = parse_feed(SAMPLE_RSS.as_bytes(), "https://example.com/feed.xml").unwrap();
        let first = &parsed.entries[0];
        assert_eq!(first.title, "First story");
        assert_eq!(first.url, "https://example.com/articles/1");
        // content:encoded -> content field (full HTML).
        assert_eq!(first.content.as_deref(), Some("<p>Full HTML content</p>"));
        // summary falls back to description when no separate summary exists.
        assert_eq!(first.summary.as_deref(), Some("Hello from the feed"));
        // media:content extracted.
        assert_eq!(first.media.len(), 1);
        assert_eq!(first.media[0].url, "https://example.com/img/1.jpg");
        // pubDate normalized to a DateTime.
        assert!(first.published_at.is_some());
    }

    #[test]
    fn parses_atom_feed_and_resolves_author() {
        let parsed = parse_feed(SAMPLE_ATOM.as_bytes(), "https://example.org/feed.atom").unwrap();
        assert_eq!(parsed.title, "Atom Example");
        // The alternate link (rel absent or "alternate"), not the self link.
        assert_eq!(parsed.site_url.as_deref(), Some("https://example.org/"));
        let entry = &parsed.entries[0];
        assert_eq!(entry.title, "Atom entry one");
        assert_eq!(entry.url, "https://example.org/entries/1");
        assert_eq!(entry.author.as_deref(), Some("Jane Doe"));
        assert_eq!(entry.content.as_deref(), Some("<p>Full content</p>"));
        assert_eq!(entry.summary.as_deref(), Some("A short summary"));
        // published preferred over updated.
        let published = entry.published_at.unwrap();
        assert_eq!(published.to_rfc3339(), "2026-06-17T09:00:00+00:00");
    }

    #[test]
    fn falls_back_to_base_url_when_title_missing() {
        let no_title = r#"<?xml version="1.0"?>
<rss version="2.0"><channel><link>https://example.com</link><description>x</description></channel></rss>"#;
        let parsed = parse_feed(no_title.as_bytes(), "https://example.com/feed.xml").unwrap();
        assert_eq!(parsed.title, "https://example.com/feed.xml");
    }

    #[test]
    fn rejects_non_feed_input() {
        let html = "<html><body><h1>Not a feed</h1></body></html>";
        let result = parse_feed(html.as_bytes(), "https://example.com/page");
        assert!(result.is_err());
    }

    #[test]
    fn resolves_relative_links_against_base() {
        // An Atom feed with a relative entry href.
        let atom = r#"<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Rel</title>
  <link href="https://example.org/"/>
  <entry>
    <title>R</title>
    <link href="/posts/1"/>
    <id>urn:uuid:r</id>
    <updated>2026-06-17T10:00:00Z</updated>
  </entry>
</feed>"#;
        let parsed = parse_feed(atom.as_bytes(), "https://example.org/feed.atom").unwrap();
        assert_eq!(parsed.entries[0].url, "https://example.org/posts/1");
    }
}
