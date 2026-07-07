//! Feed auto-discovery: scan HTML for `<link rel="alternate" type="...feed...">`.
//!
//! Uses `scraper` (html5ever + CSS selectors) rather than Livo's raw regex
//! approach. This is a superset of classic auto-discovery and mirrors what
//! MrRSS's Go reference does with `goquery`. `feedfinder` was rejected (its
//! `kuchiki 0.8` dependency is unmaintained); the function below is ~30 lines.

use scraper::{Html, Selector};
use url::Url;

use crate::api::types::FeedCandidate;

/// Finds feed links in an HTML document.
///
/// Selects `<link rel="alternate">` elements whose `type` attribute indicates
/// an RSS/Atom/JSON feed, resolves each href against `base_url`, and returns
/// ranked candidates. Returns an empty vec if `base_url` is invalid or no feed
/// links are found.
pub(crate) fn discover_feed_links(html: &str, base_url: &str) -> Vec<FeedCandidate> {
    let base = match Url::parse(base_url) {
        Ok(u) => u,
        Err(_) => return Vec::new(),
    };

    let doc = Html::parse_document(html);
    let sel = match Selector::parse("link[rel~='alternate']") {
        Ok(s) => s,
        Err(_) => return Vec::new(),
    };

    let mut candidates = Vec::new();
    for elem in doc.select(&sel) {
        let type_attr = elem.value().attr("type").unwrap_or("").to_lowercase();
        let is_feed = type_attr.contains("rss")
            || type_attr.contains("atom")
            || type_attr.contains("feed+json")
            || type_attr == "application/json";
        if !is_feed {
            continue;
        }
        let Some(href) = elem.value().attr("href") else {
            continue;
        };
        if let Ok(abs) = base.join(href) {
            candidates.push(FeedCandidate {
                url: abs.to_string(),
                title: elem.value().attr("title").map(|s| s.to_string()),
                mime_type: if type_attr.is_empty() {
                    None
                } else {
                    Some(type_attr)
                },
            });
        }
    }
    candidates
}

#[cfg(test)]
mod tests {
    use super::*;

    const HTML_WITH_FEED_LINKS: &str = r#"<html>
<head>
  <title>Some Blog</title>
  <link rel="alternate" type="application/rss+xml" title="RSS" href="/feed.xml" />
  <link rel="alternate" type="application/atom+xml" title="Atom" href="https://example.org/atom.xml" />
  <link rel="alternate" type="application/json" title="JSON Feed" href="/feed.json" />
  <link rel="stylesheet" href="/style.css" />
</head>
<body><h1>Hello</h1></body>
</html>"#;

    #[test]
    fn discovers_all_feed_link_types() {
        let found = discover_feed_links(HTML_WITH_FEED_LINKS, "https://example.org/blog");
        assert_eq!(found.len(), 3);
        let urls: Vec<&str> = found.iter().map(|c| c.url.as_str()).collect();
        assert!(urls.contains(&"https://example.org/feed.xml"));
        assert!(urls.contains(&"https://example.org/atom.xml"));
        assert!(urls.contains(&"https://example.org/feed.json"));
    }

    #[test]
    fn resolves_relative_hrefs_against_base() {
        let found = discover_feed_links(HTML_WITH_FEED_LINKS, "https://example.org/blog");
        let rss = found.iter().find(|c| c.url.ends_with("/feed.xml")).unwrap();
        assert_eq!(rss.url, "https://example.org/feed.xml");
        assert_eq!(rss.title.as_deref(), Some("RSS"));
        assert_eq!(rss.mime_type.as_deref(), Some("application/rss+xml"));
    }

    #[test]
    fn ignores_non_feed_alternate_links() {
        let html = r#"<html><head>
          <link rel="alternate" type="application/pdf" href="/doc.pdf" />
          <link rel="alternate" type="text/html" href="/mobile/" />
        </head></html>"#;
        let found = discover_feed_links(html, "https://example.org/");
        assert!(found.is_empty());
    }

    #[test]
    fn returns_empty_when_no_links() {
        let html = "<html><body><p>No links here</p></body></html>";
        let found = discover_feed_links(html, "https://example.org/");
        assert!(found.is_empty());
    }

    #[test]
    fn returns_empty_for_invalid_base_url() {
        let found = discover_feed_links(HTML_WITH_FEED_LINKS, "not a url");
        assert!(found.is_empty());
    }
}
