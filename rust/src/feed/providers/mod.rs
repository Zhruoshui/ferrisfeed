//! Special-feed providers.
//!
//! A "special feed" is a subscription where the user does not know the RSS URL
//! directly — they enter a channel/user id or an RSSHub route, and the app
//! generates the concrete `source_url` before handing off to the existing
//! `subscribe_feed_impl` pipeline. This lets us support YouTube (native RSS)
//! and RSSHub-backed sources (Bilibili, Instagram, Twitter, WeChat-MP ...)
//! without a parallel fetch/parse path.
//!
//! Ported from Livo's normalize-url approach
//! (`doc/Livo/src/main/services/feed/feed-source-provider.ts`), but reshaped
//! into an explicit `SpecialFeedProvider` trait + registry so each provider
//! is unit-testable and adding one is a two-line registry change.
//!
//! Everything here is internal (`pub(crate)`); the FRB boundary sees only
//! `api::feed::subscribe_special(provider_id, input)`.

pub(crate) mod rsshub;
pub(crate) mod youtube;

use rusqlite::Connection;

use crate::api::types::FeedType;
use crate::api::AppError;

/// A source-URL generator. Given the user's opaque `input` (a YouTube channel
/// id, an RSSHub route, ...) and a DB connection for looking up config
/// (`rsshub.base_url` for the RSSHub bridge), it returns the concrete feed URL
/// that `subscribe_feed_impl` should fetch.
///
/// Implementations must be pure aside from the `Connection` read: no HTTP, no
/// blocking I/O beyond a single settings lookup. `build_url` is called on the
/// FRB worker thread with the DB mutex held, so it must return quickly.
pub(crate) trait SpecialFeedProvider {
    /// Stable identifier used at the FRB boundary and stored in the DB row
    /// (`feeds.feed_type`). Must be lowercase and match a [`FeedType`] variant.
    #[allow(dead_code)] // Kept for symmetry with `feed_type()`; unit tests read it.
    fn id(&self) -> &'static str;

    /// The [`FeedType`] this provider produces.
    fn feed_type(&self) -> FeedType;

    /// Builds the concrete feed URL from the user's input.
    fn build_url(&self, input: &str, conn: &Connection) -> Result<String, AppError>;
}

/// Looks up a provider by its stable id. Returns `InvalidInput` if no provider
/// matches — the id came from a Dart caller so a bad value is user-input, not
/// an internal bug.
pub(crate) fn get(provider_id: &str) -> Result<&'static dyn SpecialFeedProvider, AppError> {
    match provider_id {
        "youtube" => Ok(&youtube::YoutubeProvider),
        "rsshub" => Ok(&rsshub::RsshubProvider),
        other => Err(AppError::invalid_input(format!(
            "unknown special feed provider: {other}"
        ))),
    }
}
