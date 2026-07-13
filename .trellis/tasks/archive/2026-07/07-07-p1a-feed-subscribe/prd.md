# P1a: Feed subscribe, auto-discovery & CRUD

**Parent**: `07-07-livo-frb-refactor` · **Depends on**: P0b

## Goal

Port Livo's feed subscription, auto-discovery, and CRUD. Fetch (reqwest) +
parse (feed-rs) + discover (scraper). Subscribe by URL (auto-detect feed vs
HTML page), list/edit/unsubscribe, feed normalization.

## Scope (in)

- `rust/Cargo.toml`: add `feed-rs` (sanitize), `reqwest` (rustls +
  `rustls-platform-verifier`), `scraper`, `tokio`.
- `rust/src/feed/`:
  - `fetch.rs` — async `fetch_url(url) -> bytes` (reqwest).
  - `parse.rs` — `feed-rs::parse` → `Feed`/`Entry` DTOs (map
    `content:encoded`→content, `media:*`/enclosure→media, normalize dates,
    resolve relative URLs via `url` crate).
  - `discover.rs` — `discover_feed_links(html, base_url)` via `scraper`
    (`<link rel="alternate" type="application/rss+xml">`).
  - `normalize.rs` — port `doc/Livo/src/main/database/feed-normalization.ts`.
- `rust/src/api/feed.rs` — `subscribe_feed(url)`, `discover_feeds(url)`,
  `list_feeds()`, `update_feed(id, ...)`, `delete_feed(id)`. All network fns
  are `async fn` (never `#[frb(sync)]`); errors → `AppError`.
- Flutter: rewire feed UI (sidebar/feed list, add-feed dialog with discovery
  results) against the new persisted feed api. **Remove Dart-side HTTP** from
  `reader_repository.dart` (fetching moves to Rust — contract change flagged in
  `research/frb-bridge-design.md`). Feed UI only — entry reading UI (list/detail)
  stays on `reader.rs` snapshot APIs until P2a.
- **Keep `rust/src/api/reader.rs` compiling** — the entry reading UI still uses
  its article/snapshot APIs. Removal deferred to **P2a** (supersedes P0b's
  "defer to P1a" note: removing it here would break the entry UI before P2a
  rewires it). `feed.rs` keeps reusing `reader::Feed` (FRB duplicate-identifier
  constraint) until P2a switches it to `types::Feed`.

## Acceptance Criteria

- [ ] Subscribe to a known RSS feed **and** an Atom feed; both persist + appear in list
- [ ] Subscribing to an HTML page URL triggers discovery → user picks a feed → subscribes
- [ ] Feed list / edit / unsubscribe work; unread counts render
- [ ] Network calls are async FRB fns; network/parse errors surface as `AppError` variants
- [ ] `cargo test` (parse + discover unit tests w/ fixture XML/HTML) + `flutter analyze` green

## Out of Scope

- Feed sync/refresh (P1b) · entry reading UI (P2a) · special feeds (Bilibili/
  YouTube/WeChat — P3) · OPML import (P3)

## Technical Notes

- Research: `research/rust-rss-parsing.md` (feed-rs + reqwest + scraper; reject
  `syndication`/`feedfinder`)
- Livo: `doc/Livo/src/main/services/{feed,discovery}/`, `src/main/handlers/{feed,discover}-handlers.ts`
