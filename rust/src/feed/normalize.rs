//! Feed metadata normalization.
//!
//! Ports the general parts of Livo's `feed-title.ts` (`formatFeedTitle`) and
//! `feed-normalization.ts`. Platform-specific title rules (Bilibili / Twitter /
//! Instagram RSSHub routes) are deferred to P3 (special feeds); here we only do
//! generic title fallback and site-URL validation.

use url::Url;

/// Returns a display title, falling back to the site URL host, then the feed
/// URL when the parsed title is empty/blank.
pub(crate) fn normalize_feed_title(title: &str, site_url: Option<&str>, feed_url: &str) -> String {
    let trimmed = title.trim();
    if !trimmed.is_empty() {
        return trimmed.to_string();
    }
    let fallback_url = site_url
        .filter(|s| !s.trim().is_empty())
        .unwrap_or(feed_url);
    if let Ok(url) = Url::parse(fallback_url) {
        if let Some(host) = url.host_str() {
            return host.to_string();
        }
    }
    fallback_url.trim().to_string()
}

/// Normalizes a site URL: trims and validates it parses as an absolute
/// http/https URL. Returns `None` for empty/invalid values so the caller can
/// store a default.
pub(crate) fn normalize_site_url(site_url: Option<&str>, _feed_url: &str) -> Option<String> {
    let raw = site_url?.trim();
    if raw.is_empty() {
        return None;
    }
    match Url::parse(raw) {
        Ok(u) if u.scheme() == "http" || u.scheme() == "https" => Some(u.to_string()),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keeps_non_empty_title() {
        assert_eq!(
            normalize_feed_title("  My Feed  ", None, "https://x/feed"),
            "My Feed"
        );
    }

    #[test]
    fn falls_back_to_site_url_host() {
        assert_eq!(
            normalize_feed_title("", Some("https://blog.example.com/"), "https://x/feed"),
            "blog.example.com"
        );
    }

    #[test]
    fn falls_back_to_feed_url_host() {
        assert_eq!(
            normalize_feed_title("", None, "https://feeds.example.com/rss"),
            "feeds.example.com"
        );
    }

    #[test]
    fn site_url_strips_invalid() {
        assert_eq!(normalize_site_url(Some("   "), "x"), None);
        assert_eq!(normalize_site_url(Some("not a url"), "x"), None);
        assert_eq!(normalize_site_url(Some("ftp://x"), "x"), None);
        assert_eq!(
            normalize_site_url(Some("https://example.com/"), "x"),
            Some("https://example.com/".to_string())
        );
        assert_eq!(normalize_site_url(None, "x"), None);
    }
}
