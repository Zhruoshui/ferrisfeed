# P3: Discovery & special feeds

**Parent task** (planning umbrella) for the P3 phase of the Livo FRB refactor.
Like `07-07-livo-frb-refactor`, this task defines architecture + decomposes into
child tasks; it produces no code itself. Each child runs its own
Plan -> Execute -> Finish cycle.

## Goal

Port Livo's "discovery & special feeds" domain onto the Flutter+Rust+FRB app so
users can: (a) import/export subscriptions as OPML, (b) auto-discover feeds from
a page via a discovery panel, and (c) subscribe to "special" sources that have
no vanilla RSS URL — RSSHub-backed feeds, Bilibili, YouTube, WeChat-MP
(微信公众号) — by entering a user/channel id and having the app generate the
correct feed URL, then reuse the existing subscribe/sync pipeline.

## What I already know

### Current architecture (post-MVP, master)
- `rust/src/api/feed.rs`: `discover_feeds(url)`, `subscribe_feed(url)`,
  `sync_feeds` / `refresh_all_feeds` / `refresh_feed`, CRUD. All async fns on
  FRB's tokio runtime.
- `rust/src/feed/`: `discover.rs` (scraper `<link rel=alternate>`), `fetch.rs`
  (reqwest), `parse.rs` (feed-rs), `normalize.rs`, `sync.rs` (simhash dedup),
  `simhash.rs`.
- `subscribe_feed_impl(url)`: fetch -> feed-rs parse -> normalize -> upsert.
  Idempotent on `source_url` (unique index `feeds_source_url_idx`).
- `types::Feed` / `feeds` table (migrations v1+v2): id, title, source_url,
  site_url, description, image_url, folder, category, article_view_mode,
  unread_count, article_count, last_synced_at, last_error, error_count, etag,
  last_modified, created_at. **No feed-type / provider / source-kind column.**
- Flutter UI is MVP-only: `lib/src/app/{reader_app,reader_controller,
  reader_repository,article_detail_view}.dart`. No settings UI, no discovery
  panel, no OPML UI yet.
- Spec: `.trellis/spec/backend/{error-handling,directory-structure,
  database-guidelines}.md` (FRB gotchas: freezed-for-enums,
  pub(crate)-for-non-codegenable-sigs, FRB-provides-tokio-runtime,
  stream-sink-returns-()).

### Livo reference (research in progress — subagent reading `doc/Livo/`)
- Livo service domains: `discovery/`, `bilibili/`, `video/`, `fever/`; shared
  types `rsshub-url.ts`, `bilibili-feed-url.ts`; handlers `discover`, `video`,
  `wechat-mp`; settings `wechat-rss`.
- Details pending research subagent — will be written to `research/`.

### Key architectural insight
YouTube has native RSS
(`https://www.youtube.com/feeds/videos.xml?channel_id=...`) that `feed-rs`
parses directly. Bilibili and WeChat-MP have **no public RSS**; they need either
RSSHub (`/bilibili/...`, `/wechat/mp/:id`) or a self-built bridge. So "special
feeds" are essentially **URL generators**: take a user/channel id, emit an RSS
URL, then reuse the existing `subscribe_feed_impl` + `sync_feeds_impl` pipeline.
This likely means **no schema change** for the core flow (the generated URL is
stored as a normal `source_url`), though a `feed_type` / `provider` column may
help the UI label and re-generate URLs.

## Assumptions (temporary)
- Special feeds reuse the existing subscribe/sync pipeline; we add a "provider"
  layer that maps user input -> RSS URL, not a parallel fetch/parse path.
- OPML import calls `subscribe_feed` (or a batch variant) per outline entry;
  export serializes the feed list to OPML 2.0 XML.
- Discovery panel is mostly Flutter UI over the existing `discover_feeds` API.
- RSSHub is an external service (user-configurable base URL); we do not bundle a
  RSSHub instance.

## Open Questions
1. ~~[Scope/split]~~ -> **resolved (core-first)**: OPML import/export +
   discovery panel UI + provider abstraction + RSSHub bridge (configurable
   instance) + YouTube (native RSS). Bilibili / WeChat-MP deferred to
   follow-up P3 sub-tasks (they are just RSSHub routes once the bridge exists).
2. ~~[Architecture - provider abstraction]~~ -> **resolved**: Rust-side
   provider trait + registry in `rust/src/feed/providers/`. A
   `SpecialFeedProvider` trait maps `(input, settings) -> RSS URL`;
   `api::feed` exposes `subscribe_special(provider_id, input)` which builds the
   URL then reuses `subscribe_feed_impl`. YouTube = native-RSS provider; RSSHub
   bridge = a provider that reads the configured base URL + route. Dart only
   passes `provider_id` + `input`. (Confirms/adjusts once the Livo special-feed
   abstraction research lands.)
3. ~~[Architecture - RSSHub config storage]~~ -> **resolved**: new generic
   `settings` table (`key TEXT PRIMARY KEY, value TEXT`), migration v3. RSSHub
   base URL at key `rsshub.base_url`. Reused later by P4 (AI provider config) /
   P6 (settings UI). Mirrors Livo's key-value settings-schema.
4. ~~[OPML crate]~~ -> **resolved (tentative)**: use the `opml` crate (v1.1.6,
   100k+ downloads, OPML 2.0 parse+serialize). See
   `research/opml-crate-selection.md`; final API/MSRV check deferred to P3a.
5. ~~[Schema]~~ -> **resolved**: add `feed_type TEXT` ('rss' | 'youtube' |
   'rsshub') + `provider_input TEXT` (nullable; the original channel/user id)
   to `feeds`, in migration v3 (same batch as the `settings` table). UI can
   label the source; when the RSSHub base URL changes, special-feed URLs can be
   regenerated from `provider_input` instead of orphaning the subscription.

## Decision (ADR-lite) - P3 architecture

**Context**: P3 ports Livo's discovery + special-feeds domain. Special sources
(YouTube, Bilibili, WeChat-MP) have no vanilla RSS URL; YouTube has native RSS
while Bilibili/WeChat-MP need RSSHub. The current `feeds` schema has no
feed-type column and there is no settings store. Multiple valid splits existed
for where URL-generation lives and how config/schema evolve.

**Decision** (all five open questions resolved):
1. **Scope** - core-first: OPML import/export + discovery panel UI + provider
   abstraction + RSSHub bridge + YouTube. Bilibili/WeChat-MP deferred (they are
   RSSHub routes once the bridge exists).
2. **Provider abstraction** - Rust-side `SpecialFeedProvider` trait + registry
   in `rust/src/feed/providers/`. `api::feed::subscribe_special(provider_id,
   input)` builds the URL then reuses `subscribe_feed_impl`. Dart passes only
   `provider_id` + `input`.
3. **Config storage** - new generic `settings(key TEXT PK, value TEXT)` table
   (migration v3). RSSHub base URL at `rsshub.base_url`. Reused by P4/P6.
4. **OPML** - use the `opml` crate (v1.1.6) for parse + serialize.
5. **Schema** - add `feed_type` + `provider_input` columns to `feeds`
   (migration v3, same batch as `settings`).

**Consequences**: special feeds reuse the existing fetch/parse/sync pipeline
(no parallel path); URL generation is Rust-only and unit-testable; the
`settings` table is a one-time foundation for all future config; `feed_type` /
`provider_input` let the UI label sources and survive RSSHub-instance changes.
Trade-off: P3c carries the settings-table + migration v3 + provider trait +
YouTube provider + Flutter UI in one child (tightly coupled); Bilibili/WeChat-MP
wait. **Confirmed against Livo** - see `research/livo-special-feeds-reference.md`:
Livo has no provider trait (just a `getNormalizedFeedUrl` fn + `upstreamUrl`
field), so our trait is an explicit improvement; the `opml` crate replaces
Livo's hand-rolled parser; `settings` table + `feed_type`/`provider_input`
mirror Livo's `rsshubInstance` setting + `upstreamUrl`/`fetchSource` fields. No
ADR changes needed.

## Requirements (evolving)

In-scope for this P3 phase (core-first, per the scope decision). Proposed child
tasks (each its own Plan -> Execute -> Finish; dependency order):

| # | Child task | Depends on | One-line scope |
|---|---|---|---|
| 1 | `p3a-opml-import-export` | - | OPML 2.0 parse + serialize via the `opml` crate (Rust); batch `subscribe_feed` on import; Flutter import/export UI. |
| 2 | `p3b-discovery-panel` | - | Flutter discovery panel over the existing `discover_feeds` API (enter URL -> pick candidate -> subscribe). |
| 3 | `p3c-special-feed-providers` | - | migration v3 (`settings` table + `feeds.feed_type` / `provider_input`) + `SpecialFeedProvider` trait/registry + RSSHub bridge (reads `rsshub.base_url`) + YouTube provider (native RSS) + `subscribe_special` API + Flutter subscribe-by-id UI. |

Follow-up P3 sub-tasks (NOT created this round): Bilibili provider, WeChat-MP
provider (both are RSSHub routes once `p3c` lands).

## Acceptance Criteria (evolving)
- [x] Architecture decision recorded (ADR-lite above): provider abstraction +
      RSSHub config strategy + OPML crate choice + schema-impact decision.
- [ ] Child tasks created for each in-scope sub-area, each with its own
      prd.md + acceptance criteria.
- [ ] Parent task stays in `planning` as coordinating umbrella; archived once
      children are done.

## Definition of Done (team quality bar)
- Tests added/updated (Rust unit tests + Dart where apt)
- `flutter analyze` + `cargo test` + `bash scripts/frb.sh` green
- Docs/notes updated if behavior changes
- Per-task trellis flow respected (Plan -> Execute -> Finish)

## Out of Scope (explicit — deferred)
- Fever API sync, Supabase cloud sync, multi-account/auth (separate from P3)
- AI features (P4), Agent (P5), polish (P6)
- Bundling a RSSHub instance (we use an external user-configured one)

## Technical Notes
- Livo schema reference: `doc/Livo/src/main/database/sqlite-schema.ts` (check
  for feed-type columns — pending research)
- Current Rust feed module: `rust/src/feed/`, api: `rust/src/api/{feed,types}.rs`,
  db: `rust/src/db/{migrations,repositories/feed}.rs`
- FRB pinned to git rev `254b193`; codegen via `bash scripts/frb.sh` after every
  `api/**` change
- CodeGraph index at repo root
- Research subagent investigating Livo's discovery / opml / rsshub / bilibili /
  youtube / wechat-mp + special-feed abstraction + settings + schema ->
  `research/`
