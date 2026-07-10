//! YouTube special-feed provider.
//!
//! YouTube publishes native RSS at
//! `https://www.youtube.com/feeds/videos.xml?channel_id={id}` for every
//! channel, so the "provider" here is a pure URL template: no settings, no
//! config, no HTTP. `feed-rs` parses the response directly through the normal
//! `subscribe_feed_impl` path.
//!
//! Input must be a canonical `UC...`-style channel id (24 chars, base64url
//! alphabet). The handle-shaped variants (`@channelname`, `/user/foo`, custom
//! URLs) require an authenticated API round-trip to resolve into a channel id;
//! that's out of scope for P3c (see the "Out of Scope" list in the prd).

use rusqlite::Connection;

use crate::api::types::FeedType;
use crate::api::AppError;
use crate::feed::providers::SpecialFeedProvider;

const YOUTUBE_FEED_URL_PREFIX: &str = "https://www.youtube.com/feeds/videos.xml?channel_id=";

pub(crate) struct YoutubeProvider;

impl SpecialFeedProvider for YoutubeProvider {
    fn id(&self) -> &'static str {
        "youtube"
    }

    fn feed_type(&self) -> FeedType {
        FeedType::Youtube
    }

    fn build_url(&self, input: &str, _conn: &Connection) -> Result<String, AppError> {
        let channel_id = input.trim();
        if channel_id.is_empty() {
            return Err(AppError::invalid_input(
                "YouTube channel id must not be empty",
            ));
        }
        if !is_canonical_channel_id(channel_id) {
            return Err(AppError::invalid_input(format!(
                "YouTube channel id must start with 'UC' and be 24 characters, got: {channel_id}"
            )));
        }
        Ok(format!("{YOUTUBE_FEED_URL_PREFIX}{channel_id}"))
    }
}

/// Canonical channel ids start with `UC` and are 24 base64url-alphabet chars.
fn is_canonical_channel_id(id: &str) -> bool {
    id.len() == 24
        && id.starts_with("UC")
        && id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
}

#[cfg(test)]
mod tests {
    use super::*;

    fn conn() -> Connection {
        Connection::open_in_memory().unwrap()
    }

    #[test]
    fn builds_channel_url() {
        let out = YoutubeProvider
            .build_url("UCXuqSBlHAE6Xw-yeJA0Tunw", &conn())
            .unwrap();
        assert_eq!(
            out,
            "https://www.youtube.com/feeds/videos.xml?channel_id=UCXuqSBlHAE6Xw-yeJA0Tunw"
        );
    }

    #[test]
    fn trims_input() {
        let out = YoutubeProvider
            .build_url("  UCXuqSBlHAE6Xw-yeJA0Tunw \n", &conn())
            .unwrap();
        assert!(out.ends_with("channel_id=UCXuqSBlHAE6Xw-yeJA0Tunw"));
    }

    #[test]
    fn rejects_empty() {
        let err = YoutubeProvider.build_url("   ", &conn()).unwrap_err();
        assert!(matches!(err, AppError::InvalidInput(_)));
    }

    #[test]
    fn rejects_handle_shaped_input() {
        // Handles like "@somechannel" require an API resolve step — out of
        // scope for P3c. The provider surfaces a clear error so the UI can
        // hint at the required format.
        let err = YoutubeProvider
            .build_url("@somechannel", &conn())
            .unwrap_err();
        assert!(matches!(err, AppError::InvalidInput(_)));
    }

    #[test]
    fn rejects_wrong_length() {
        let err = YoutubeProvider.build_url("UCshort", &conn()).unwrap_err();
        assert!(matches!(err, AppError::InvalidInput(_)));
    }

    #[test]
    fn feed_type_is_youtube() {
        assert_eq!(YoutubeProvider.feed_type(), FeedType::Youtube);
        assert_eq!(YoutubeProvider.id(), "youtube");
    }
}
