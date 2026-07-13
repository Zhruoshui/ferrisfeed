# Refactor Livo RSS reader onto Flutter + Rust + flutter_rust_bridge

## Goal

Rebuild the Livo RSS reader (currently Electron 33 + React 19 + TypeScript +
better-sqlite3) as a cross-platform app on the current project's stack:
**Flutter** (UI) + **Rust** (core logic / persistence / network) bridged via
**`flutter_rust_bridge`** (FRB). Livo is feature-rich, so this parent task
defines the architecture and decomposes the work into child tasks (one per
feature domain). Each child task runs its own Plan → Execute → Finish cycle.

## What I already know

### Source project — Livo (`doc/Livo/`)
A mature, local-first RSS reader. Tech: Electron + React 19 + TS 5.9, Vite,
Zustand + TanStack Query + React Router, Tailwind, better-sqlite3, OpenAI SDK,
Vitest.

Feature domains (from `src/main/services/`):
- `feed/` — RSS/Atom subscription, sync, normalization
- `entry/` — article entries, read/unread, star
- `discovery/` — feed auto-discovery from a URL
- `ai/` — summary, translation, bilingual, chat Q&A (+ `rag/`)
- `agent/` — autonomous tool-calling agent: harness, loop, tool-registry,
  policy-guard, memory, trace-store (`src/main/agent/`)
- `account/` + `auth/` — multi-account, Google OAuth, Supabase
- `bilibili/`, `video/` — Bilibili / YouTube / video feeds
- `fever/` — Fever-API compatible server sync
- `reading-activity/` — reading tracking + heatmap
- `system/`, `actions/` — system services, user actions

Other layers:
- `src/main/database/` — SQLite schema, repositories, cleanup, **simhash
  dedup**, feed-normalization, row-mappers, indexes
- `src/main/handlers/` — IPC handlers (feed, entry, discover, ai, agent, auth,
  fever, readability, reader, settings, updater, video, websocket, wechat-mp,
  notification, reading-activity, task …)
- `src/shared/` — types (account, agent, ai, app, entry, feed, fever, task),
  IPC contracts, settings-schema, ai-endpoint, url-policy, deep-link,
  bilibili-feed-url, rsshub-url, supabase-config, i18n-completeness
- `src/renderer/` — large React UI: entry list with **grid / linear / social /
  wide** layouts, AI chat panels, discover, quick-search, settings (appearance,
  reading, AI, translation, privacy, data, shortcuts, accounts, fever,
  wechat-rss, agent-permissions), command palette, media/video player, OPML
  import, i18n (en, zh-CN), notifications

Key dependencies: `rss-parser`, `better-sqlite3`, `openai` (multi-provider:
OpenAI/Anthropic/DeepSeek/智谱/Ollama/custom), `@mozilla/readability` +
`dompurify` + `linkedom`, `electron-store`, `electron-updater`, `socket.io-client`,
`@supabase/supabase-js`.

### Target project — current `rss_reader/`
A thin scaffold, NOT a port yet:
- Flutter deps: `http`, `shared_preferences`, `flutter_widget_from_html`,
  `html`, `url_launcher`, `webview_flutter`, `rust_lib_rss_reader` (path),
  `flutter_rust_bridge` (git rev `254b193`)
- Rust deps: `flutter_rust_bridge` (same rev), `chrono`, `serde`, `serde_json`,
  `url`, `uuid` — **no SQLite, no RSS parser, no HTTP client, no AI client yet**
- `rust/src/api/simple.rs` — `greet()` + `init_app()`
- `rust/src/api/reader.rs` — in-memory **JSON-snapshot** model (Feed, Article,
  ArticleListItem, FeedDraft, ArticleDraft, ImportFeedResult); FRB `#[frb(sync)]`
  fns: `empty_reader_snapshot_json`, `decode_reader_snapshot`, `list_articles`,
  `import_feed` … — **no persistence**: snapshots are passed as JSON strings
- `lib/src/app/` — `reader_app.dart`, `reader_controller.dart`,
  `reader_repository.dart`, `article_detail_view.dart`
- FRB config (`flutter_rust_bridge.yaml`): `rust_input: crate::api`,
  `rust_root: rust/`, `dart_output: lib/src/rust`
- Platforms configured: android, ios, linux, macos, windows (web dropped per
  recent commits)

## Assumptions (temporary)

- Rust becomes the "main process" equivalent: persistence, feed fetching/parsing,
  AI calls, agent runtime. Flutter is the "renderer". FRB replaces IPC.
- SQLite lives in Rust (mirrors Livo's better-sqlite3-in-main-process design).
- The existing in-memory `reader.rs` snapshot model is a throwaway prototype to
  be replaced by a real persisted model.
- We port feature-by-feature in child tasks; the parent task only lands
  architecture + the task breakdown.

## Open Questions

1. ~~[Architecture — Rust DB]~~ → **resolved**, see Decision (ADR-lite) — Architecture
2. ~~[Architecture — RSS parsing]~~ → **resolved**, see Decision (ADR-lite) — Architecture
3. ~~[Architecture — FRB bridge design]~~ → **resolved**, see Decision (ADR-lite) — Architecture
4. **[Architecture — Readability]** (deferred to P2 child task) Livo uses
   `@mozilla/readability`+`dompurify`. Rust `readability` crate vs Dart-side
   (`flutter_widget_from_html` + `html` already present)?
5. **[Task split granularity]** One child task per Livo service domain, or
   coarser (group related domains)?

## Research References

* [`research/rust-sqlite-binding.md`](research/rust-sqlite-binding.md) — use
  `rusqlite` (bundled) + `rusqlite_migration`, one `Mutex<Connection>` via
  `OnceLock`, plain `fn` (worker pool) or `async fn` + `spawn_blocking_with`;
  sqlx rejected (offline-cache friction), sea-orm rejected (breaks FRB #3265).
* [`research/rust-rss-parsing.md`](research/rust-rss-parsing.md) — use
  `feed-rs` 2.4.0 (sanitize) + `reqwest` 0.13 (rustls +
  `rustls-platform-verifier`) + `scraper` 0.27 for auto-discovery; reject
  `syndication` (stale) and `feedfinder` (unmaintained `kuchiki`).
* [`research/frb-bridge-design.md`](research/frb-bridge-design.md) — async by
  default, `#[frb(sync)]` only for tiny lookups; `StreamSink<SyncProgress>`
  for sync events; `AppError` enum replaces `ReaderError` struct;
  `api/{error,types,app,feed,entry,settings}.rs` over `db/`+`services/`+`feed/`.

## Technical Approach (converged from research)

**Rust = Livo's "main process"; Flutter = "renderer"; FRB = IPC replacement.**

- **Persistence** — `rusqlite` (`bundled` → static SQLite w/ FTS5/JSON1 on all
  5 platforms, parity with Livo's better-sqlite3 bundling). One
  `Mutex<Connection>` in a `OnceLock` static, opened in `init_app()` with
  `WAL` + `foreign_keys=ON` + `synchronous=NORMAL` (mirrors
  `doc/Livo/src/main/database/sqlite-adapter.ts`). Migrations via
  `rusqlite_migration` (or `refinery` if we want Livo's named-history table),
  ported verbatim from `sqlite-schema.ts`'s 9 migrations. Simhash dedup stays
  in-memory (parity with Livo). FTS5 optional (Livo uses `LIKE`; FTS is an
  enhancement, not a port requirement).
- **Feed fetch/parse** — `reqwest` (rustls + platform-verifier, async) fetches;
  `feed-rs` parses (RSS 2.0/Atom/RSS 1.0/JSON Feed, maps `content:encoded` →
  content, `media:*`/enclosure → media, normalizes dates, resolves relative
  URLs); `scraper`-based `discover_feed_links` for auto-discovery. All network
  calls are `async fn` (never `#[frb(sync)]`). Moves HTTP out of Dart
  (`reader_repository.dart` currently fetches in Dart — changes the
  `importFeed` contract).
- **FRB bridge** — async-by-default; `#[frb(sync)]` only for tiny pure/indexed
  lookups (defaults, single PK reads, `mark_read`/`toggle_star`). Wrap blocking
  rusqlite in `async fn` + `spawn_blocking_with`. `StreamSink<SyncProgress>`
  mirrors Livo's `FeedRefreshProgressPayload`. Project-wide `AppError` enum in
  `rust/src/api/error.rs` replaces the `ReaderError` struct; `anyhow` internal
  to services. Module layout: `api/{error,types,app,feed,entry,settings}.rs`
  thin wrappers over `db/` + `services/` + `feed/` (mirrors Livo's
  handler/domain split). Codegen `flutter_rust_bridge_codegen gen` after every
  api change; keep `auto_upgrade_dependency: false` + rev `254b193`; add a
  `make frb` target.
- **Mobile caveat** — Android x86_64 emulator needs a `build.rs` linking
  `clang_rt.builtins-x86_64-android` (FRB issue #1719) for any bundled-SQLite
  choice; physical arm64 devices are unaffected.

## Decision (ADR-lite) — Architecture

**Context**: Three independent research passes (SQLite binding, RSS parsing,
FRB bridge) needed before P0 can start; multiple viable options existed.
**Decision**: rusqlite+bundled (+rusqlite_migration) behind `Mutex<Connection>`;
feed-rs + reqwest(rustls) + scraper; FRB async-by-default with `StreamSink`
progress, `AppError` enum, `api/*` thin-wrapper module layout.
**Consequences**: Rejected sqlx (offline-cache friction during schema churn),
sea-orm (breaks FRB codegen #3265), syndication/feedfinder (stale/unmaintained).
Dart-side HTTP fetch in `reader_repository.dart` goes away. The existing
`ReaderError` struct + `#[frb(sync)]`-everywhere pattern in `reader.rs` is
abandoned (replaced, not extended). One Android-emulator `build.rs` fix
required up-front.

## Decision (ADR-lite) — Scope

**Context**: Livo is feature-rich (14 service domains + agent + full UI); a
1:1 port is long and risks late architecture rework on the hard AI/agent parts.
**Decision**: Phased MVP-first. This parent task delivers **P0 (foundation) +
P1 (feed mgmt & sync) + P2 (entry reading)** as a usable core RSS reader.
P3–P6 (discovery/special feeds, AI, agent, polish) become **separate child
tasks** iterated later.
**Consequences**: Architecture must leave extension points for AI/agent (e.g.
service-registry pattern, settings store) without building them now. Faster
de-risking; AI/agent decisions deferred to their own brainstorms.

## Requirements (evolving)

Proposed phasing (to be confirmed via scope question):

- **P0 — Foundation**: FRB/Rust module layout; SQLite layer in Rust + schema
  migration; core data model (Feed, Entry, Category/Folder) ported from Livo's
  schema; repository CRUD exposed over FRB. Replaces the JSON-snapshot prototype.
- **P1 — Feed management & sync**: RSS/Atom parse (`feed-rs`?), subscribe,
  auto-discovery, periodic sync, feed list CRUD.
- **P2 — Entry reading**: entry list (linear), read/unread, star, detail view
  (rendered HTML), prev/next, full-text search.
- **P3 — Discovery & special feeds**: discovery panel, OPML import/export,
  RSSHub, Bilibili/YouTube/WeChat-MP.
- **P4 — AI**: multi-provider config, summary, translation, bilingual, chat Q&A
  (+ RAG).
- **P5 — Agent**: tool-registry, harness/loop, policy-guard, memory, trace.
- **P6 — Polish & platform**: i18n, settings UI, reading-activity/heatmap,
  notifications, command palette, shortcuts, updater.

## Acceptance Criteria (evolving)

- [ ] Architecture decision recorded (DB, RSS, AI, readability) as ADR-lite
- [ ] Child tasks created for each in-scope phase/domain
- [ ] P0 lands: persisted Feed/Entry CRUD works end-to-end through FRB
- [ ] Each child task has its own prd.md + acceptance criteria

## Definition of Done (team quality bar)

- Tests added/updated (Rust unit tests + Dart widget/integration where apt)
- `flutter analyze` + `cargo test` + FRB codegen green
- Docs/notes updated if behavior changes
- Per-task trellis flow respected (Plan → Execute → Finish)

## Implementation Plan (child tasks — MVP)

Each child runs its own Plan → Execute → Finish cycle. Dependency order:

| # | Child task | Depends on | One-line scope |
|---|---|---|---|
| 1 | `07-07-p0a-frb-scaffolding` | — | FRB skeleton: `AppError` enum, shared DTO `types.rs`, `api/*` module layout, `make frb` target, Android `build.rs` fix. No DB yet. |
| 2 | `07-07-p0b-sqlite-persistence` | P0a | `rusqlite`+bundled, `Mutex<Connection>`, migrations (MVP subset of Livo schema), Feed/Entry/Category repos, `init_app()` opens DB. **Retires the JSON-snapshot prototype.** |
| 3 | `07-07-p1a-feed-subscribe` | P0b | `reqwest`+`feed-rs`+`scraper`: subscribe, auto-discovery, feed CRUD, normalization. Flutter feed UI rewire. |
| 4 | `07-07-p1b-feed-sync` | P1a | `sync_feeds` async + `StreamSink<SyncProgress>`, idempotent upsert, simhash dedup (in-memory). Flutter refresh UI. |
| 5 | `07-07-p2a-entry-reading` | P1b | Entry list (linear, filters, pagination), read/unread, star, prev/next, detail view (HTML). Rewire Flutter reading UI to persisted model. |
| 6 | `07-07-p2b-entry-search` | P2a | `search_entries` (LIKE parity with Livo) + Flutter quick-search. |

**Parent task deliverable**: architecture decision + research + this breakdown +
seeded child PRDs. The parent produces no code itself; implementation lives in
the children. The parent stays in `planning` as the coordinating umbrella and
is archived once the MVP children are done.

## Deferred roadmap (future child tasks — NOT created yet)

Each gets its own brainstorm when reached (architecture for AI/agent/special-feeds
deferred per the scope decision):

- **P3 — Discovery & special feeds**: discovery panel, OPML import/export,
  RSSHub, Bilibili, YouTube, WeChat-MP.
- **P4 — AI**: multi-provider config (OpenAI/Anthropic/DeepSeek/智谱/Ollama),
  summary, translation, bilingual, chat Q&A (+ RAG).
- **P5 — Agent**: tool-registry, harness/loop, policy-guard, memory, trace.
- **P6 — Polish & platform**: i18n (en/zh-CN), settings UI, reading-activity
  heatmap, notifications, command palette, shortcuts, auto-updater, FTS5,
  grid/social/wide layouts, readability extraction.



## Out of Scope (explicit — deferred to later child tasks)

> See **Deferred roadmap** above for the phased plan. These items are excluded
> from the MVP parent task and will become their own child tasks later:

- AI features (P4): summary, translation, bilingual, chat Q&A, RAG
- Agent system (P5): tool-registry, harness/loop, policy-guard, memory, trace
- Discovery panel + special feeds (P3): RSSHub, Bilibili, YouTube, WeChat-MP
- OPML import/export (P3)
- Fever API sync, Supabase cloud sync, multi-account/auth (Google OAuth)
- Reading-activity heatmap, notifications center, command palette, global
  shortcuts, auto-updater mechanics (P6 polish)
- Web platform (already dropped)
- Readability full-text extraction (re-evaluate at P2; MVP renders feed content)

## Technical Notes

- Livo schema reference: `doc/Livo/src/main/database/sqlite-schema.ts`,
  `row-mappers.ts`, `indexes.ts`, `entry-simhash.ts`, `feed-normalization.ts`
- Livo IPC contracts: `doc/Livo/src/shared/ipc-contracts.ts`,
  `doc/Livo/src/shared/types/`
- Current Rust API: `rust/src/api/{mod,simple,reader}.rs`
- Current Dart app: `lib/src/app/`, `lib/src/rust/frb_generated*.dart`
- FRB pinned to git rev `254b193` (matches `Cargo.toml` + `pubspec.yaml`)
- CodeGraph index exists at repo root (`.codegraph/`) — use it to navigate
- Trellis spec layers: `.trellis/spec/{backend,frontend,guides}/` (TS/React-
  oriented; will need Flutter/Rust adaptation as we go)
