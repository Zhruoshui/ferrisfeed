//! RSSHub special-feed provider.
//!
//! RSSHub (<https://docs.rsshub.app>) turns any supported source into an RSS
//! feed at `{base}/{route}`. The base URL is user-configurable (defaults to
//! `https://rsshub.app`, the public community instance) and stored in the
//! `settings` table under the key [`RSSHUB_BASE_URL_KEY`]. Users pick their
//! route from the RSSHub docs; e.g.
//! `bilibili/user/dynamic/2267573` → `{base}/bilibili/user/dynamic/2267573`.
//!
//! Ported from Livo's `settings.general.rsshubInstance` +
//! `normalizeFeedUrl(feed.url, rsshubInstance)` pair
//! (`doc/Livo/src/main/services/feed/feed-source-provider.ts`). Livo stores the
//! final URL; we store both `source_url` and `provider_input`, so switching
//! the RSSHub base URL later can re-derive `source_url` without orphaning the
//! subscription (that rebuild is deferred; the schema already supports it).

use rusqlite::Connection;

use crate::api::types::FeedType;
use crate::api::AppError;
use crate::db::repositories::settings;
use crate::feed::providers::SpecialFeedProvider;

/// The settings key holding the user's RSSHub base URL.
pub(crate) const RSSHUB_BASE_URL_KEY: &str = "rsshub.base_url";

/// Public RSSHub instance used when the user has not configured their own.
/// This is the same default Livo ships (`DEFAULT_RSSHUB_INSTANCE`).
pub(crate) const DEFAULT_RSSHUB_BASE_URL: &str = "https://rsshub.app";

pub(crate) struct RsshubProvider;

impl SpecialFeedProvider for RsshubProvider {
    fn id(&self) -> &'static str {
        "rsshub"
    }

    fn feed_type(&self) -> FeedType {
        FeedType::Rsshub
    }

    fn build_url(&self, input: &str, conn: &Connection) -> Result<String, AppError> {
        let route = input.trim();
        if route.is_empty() {
            return Err(AppError::invalid_input("RSSHub route must not be empty"));
        }
        // Whole-URL inputs are almost certainly a mistake (either the user
        // pasted the finished URL — should just use "Add feed" — or they
        // pasted a docs example with the scheme). Bail with a clear message
        // rather than producing `{base}/https://...` and confusing the fetch
        // layer.
        if route.starts_with("http://") || route.starts_with("https://") {
            return Err(AppError::invalid_input(
                "RSSHub input must be a route like 'bilibili/user/dynamic/123', not a full URL",
            ));
        }

        let base = resolve_base_url(conn)?;
        Ok(join_base_and_route(&base, route))
    }
}

/// Reads the user-configured RSSHub base URL, falling back to
/// [`DEFAULT_RSSHUB_BASE_URL`] if unset. The stored value has trailing
/// whitespace/slashes stripped so the resulting URL is well-formed.
pub(crate) fn resolve_base_url(conn: &Connection) -> Result<String, AppError> {
    let stored = settings::get_setting(conn, RSSHUB_BASE_URL_KEY)?;
    let value = stored
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| DEFAULT_RSSHUB_BASE_URL.to_string());
    Ok(value.trim_end_matches('/').to_string())
}

/// Joins a normalized base URL (no trailing slash) with a route, tolerating a
/// leading slash on the route.
fn join_base_and_route(base: &str, route: &str) -> String {
    let route = route.strip_prefix('/').unwrap_or(route);
    format!("{base}/{route}")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn conn_with(base: Option<&str>) -> Connection {
        let mut conn = Connection::open_in_memory().unwrap();
        crate::db::migrations::run(&mut conn).unwrap();
        if let Some(url) = base {
            settings::set_setting(&conn, RSSHUB_BASE_URL_KEY, Some(url)).unwrap();
        }
        conn
    }

    #[test]
    fn defaults_to_public_instance_when_unset() {
        let out = RsshubProvider
            .build_url("bilibili/user/dynamic/123", &conn_with(None))
            .unwrap();
        assert_eq!(out, "https://rsshub.app/bilibili/user/dynamic/123");
    }

    #[test]
    fn uses_stored_base_url() {
        let out = RsshubProvider
            .build_url(
                "bilibili/user/dynamic/123",
                &conn_with(Some("https://my-rsshub.example.com")),
            )
            .unwrap();
        assert_eq!(
            out,
            "https://my-rsshub.example.com/bilibili/user/dynamic/123"
        );
    }

    #[test]
    fn strips_trailing_slash_on_base() {
        let out = RsshubProvider
            .build_url(
                "bilibili/user/dynamic/123",
                &conn_with(Some("https://my-rsshub.example.com/")),
            )
            .unwrap();
        assert_eq!(
            out,
            "https://my-rsshub.example.com/bilibili/user/dynamic/123"
        );
    }

    #[test]
    fn tolerates_leading_slash_on_route() {
        let out = RsshubProvider
            .build_url("/bilibili/user/dynamic/123", &conn_with(None))
            .unwrap();
        assert_eq!(out, "https://rsshub.app/bilibili/user/dynamic/123");
    }

    #[test]
    fn trims_input() {
        let out = RsshubProvider
            .build_url("  bilibili/user/dynamic/123 \n", &conn_with(None))
            .unwrap();
        assert!(out.ends_with("/bilibili/user/dynamic/123"));
    }

    #[test]
    fn rejects_empty_route() {
        let err = RsshubProvider
            .build_url("   ", &conn_with(None))
            .unwrap_err();
        assert!(matches!(err, AppError::InvalidInput(_)));
    }

    #[test]
    fn rejects_absolute_url_input() {
        // Full URLs are a common mistake; the error message tells the user
        // what format we expect.
        let err = RsshubProvider
            .build_url(
                "https://rsshub.app/bilibili/user/dynamic/123",
                &conn_with(None),
            )
            .unwrap_err();
        assert!(matches!(err, AppError::InvalidInput(_)));
    }

    #[test]
    fn falls_back_when_stored_base_is_blank() {
        // A cleared setting (empty string) reverts to the default rather than
        // producing an invalid `//bilibili/...` URL.
        let out = RsshubProvider
            .build_url("bilibili/user/dynamic/123", &conn_with(Some("   ")))
            .unwrap();
        assert_eq!(out, "https://rsshub.app/bilibili/user/dynamic/123");
    }
}
