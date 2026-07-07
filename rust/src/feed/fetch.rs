//! HTTP fetching via reqwest (rustls + platform-verifier).
//!
//! Keeps a single shared `reqwest::Client` (rustls with the OS trust store via
//! `rustls-platform-verifier`, no OpenSSL to cross-compile). All transport
//! failures (DNS, timeout, TLS, non-2xx) map to [`AppError::Network`]; invalid
//! URLs map to [`AppError::InvalidInput`]. This module is NOT exposed across
//! the FRB boundary — only `&[u8]`/`String` cross out.

use std::sync::OnceLock;
use std::time::Duration;

use crate::api::AppError;

static CLIENT: OnceLock<reqwest::Client> = OnceLock::new();

fn client() -> &'static reqwest::Client {
    CLIENT.get_or_init(|| {
        reqwest::Client::builder()
            .timeout(Duration::from_secs(30))
            .redirect(reqwest::redirect::Policy::limited(5))
            .build()
            .expect("failed to build reqwest client")
    })
}

/// Fetches `url`, returning the response body bytes and the `content-type`.
///
/// Only `http`/`https` URLs are accepted (mirrors the Flutter-side
/// `isSafeExternalUrl` scheme guard at the other boundary). A non-2xx status
/// becomes `AppError::Network { url, status, message }`; transport errors
/// (DNS, timeout, TLS) also become `Network` with `status = 0`.
pub(crate) async fn fetch_url(url: &str) -> Result<(Vec<u8>, String), AppError> {
    let parsed = url::Url::parse(url)
        .map_err(|e| AppError::invalid_input(format!("invalid URL: {e}")))?;
    if parsed.scheme() != "http" && parsed.scheme() != "https" {
        return Err(AppError::invalid_input("URL must use http or https"));
    }

    let resp = client()
        .get(parsed.as_str())
        .header(
            "accept",
            "application/rss+xml, application/atom+xml, application/json, \
             application/xml, text/xml;q=0.9, */*;q=0.8",
        )
        .header("user-agent", "rss_reader/1.0 (flutter+rust)")
        .send()
        .await
        .map_err(|e| AppError::Network {
            url: url.to_string(),
            status: 0,
            message: e.to_string(),
        })?;

    let status = resp.status().as_u16();
    if !resp.status().is_success() {
        let message = resp
            .status()
            .canonical_reason()
            .unwrap_or("request failed")
            .to_string();
        return Err(AppError::Network {
            url: url.to_string(),
            status,
            message,
        });
    }

    let content_type = resp
        .headers()
        .get(reqwest::header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("")
        .to_string();

    let bytes = resp
        .bytes()
        .await
        .map_err(|e| AppError::Network {
            url: url.to_string(),
            status: 0,
            message: e.to_string(),
        })?;

    Ok((bytes.to_vec(), content_type))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// End-to-end smoke: fetches a real feed over HTTP and parses it. Ignored by
    /// default (network-dependent); run with `cargo test -- --ignored`.
    #[tokio::test]
    #[ignore = "requires network; run with --ignored"]
    async fn fetch_and_parse_real_feed() {
        let url = "https://feeds.bbci.co.uk/news/rss.xml";
        let (bytes, content_type) = fetch_url(url).await.unwrap();
        assert!(!bytes.is_empty());
        eprintln!("content-type: {content_type}");
        let feed = crate::feed::parse::parse_feed(&bytes, url).unwrap();
        eprintln!("title: {}, entries: {}", feed.title, feed.entries.len());
        assert!(!feed.title.is_empty());
        assert!(!feed.entries.is_empty());
    }
}
