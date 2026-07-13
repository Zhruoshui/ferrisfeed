# P3c: Special-feed providers (RSSHub + YouTube)

**Parent**: `07-09-p3-discovery-special-feeds` · **Depends on**: -

## Goal

Land the special-feed provider abstraction and the first two providers: YouTube
(native RSS) and an RSSHub bridge. Users subscribe by entering a channel/user id
(or RSSHub route); the app generates the RSS URL and reuses the existing
subscribe/sync pipeline. Also lands the `settings` table + `feeds` schema
columns the parent ADR decided on.

## Scope (in)

- **Migration v3** (`rust/src/db/migrations.rs`): `settings(key TEXT PK, value
  TEXT)` table; `feeds` gains `feed_type TEXT NOT NULL DEFAULT 'rss'` +
  `provider_input TEXT`.
- **Provider abstraction** (`rust/src/feed/providers/`): a `SpecialFeedProvider`
  trait (`fn id()`, `fn build_url(input, settings) -> Result<String>`) + a
  registry. `api::feed::subscribe_special(provider_id, input)` builds the URL
  (reading `rsshub.base_url` from `settings` for the RSSHub provider) then
  reuses `subscribe_feed_impl`, persisting `feed_type` + `provider_input`.
- **Providers**: `YoutubeProvider`
  (`https://www.youtube.com/feeds/videos.xml?channel_id={input}`) and
  `RsshubProvider` (input = a route like `bilibili/user/dynamic/123` ->
  `{base_url}/{route}`).
- **Settings API**: `get_setting(key)` / `set_setting(key, value)` (or a typed
  RSSHub-config getter/setter) so Flutter can configure the RSSHub base URL.
- **Flutter**: subscribe-by-id UI (pick provider -> enter id -> subscribe) + a
  RSSHub base URL config field.

## Acceptance Criteria

- [x] Migration v3 applies cleanly on top of v2; existing feeds get
      `feed_type='rss'`, `provider_input=NULL`.
- [x] `subscribe_special("youtube", <channel_id>)` subscribes and the feed syncs
      entries via the existing pipeline; `feed_type='youtube'`, `provider_input`
      stored.
- [x] `subscribe_special("rsshub", <route>)` builds `{base_url}/{route}` using
      the configured `rsshub.base_url` and subscribes.
- [x] RSSHub base URL is persisted in `settings` and read by the provider.
- [x] Provider URL-building is unit-tested in Rust (no network needed).
- [x] `cargo test` + `flutter analyze` + `bash scripts/frb.sh` green.

## Out of Scope

- Bilibili / WeChat-MP providers (follow-up P3 sub-tasks - they are RSSHub
  routes once this lands)
- RSSHub route catalog / autocomplete (future)
- Auto-rebuilding special-feed URLs when the RSSHub base changes (schema
  supports it via `provider_input`; the rebuild function is a later enhancement)
- YouTube API key / playlist subscriptions (native channel RSS covers the
  common case)

## Technical Notes

- Provider trait + registry in `rust/src/feed/providers/`; reuse
  `subscribe_feed_impl` + `sync_feeds_impl` (no parallel fetch/parse path).
- Settings: `settings(key, value)` table; add a `settings` module under
  `rust/src/db/repositories/`. RSSHub base default e.g. `https://rsshub.app`.
- Livo special-feed abstraction + settings-schema + bilibili/youtube/wechat
  reference: see parent `research/` (pending subagent) - `doc/Livo/src/shared/
  types/{rsshub-url,bilibili-feed-url}.ts`, `src/main/services/{bilibili,video}`,
  `src/shared/settings-schema.ts`.
- FRB codegen (`bash scripts/frb.sh`) after every `api/**` change.
