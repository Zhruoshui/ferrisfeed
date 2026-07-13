# P3b: Discovery panel

**Parent**: `07-09-p3-discovery-special-feeds` · **Depends on**: -

## Goal

Port Livo's discovery panel UI. Let the user enter a website URL, see the
candidate feeds discovered via the existing `discover_feeds` API, and subscribe
to one. The Rust backend already exists (P1a `discover_feeds`); this task is
mostly Flutter UI.

## Scope (in)

- Flutter: a discovery panel/dialog - URL input -> calls `discover_feeds(url)`
  -> shows candidate list (`FeedCandidate { url, title, mime_type }`) ->
  selecting one calls `subscribe_feed(url)`.
- Loading / empty (no candidates) / error states.
- Entry point from the feed management UI (e.g., a "Discover feeds" action next
  to "Add by URL").

## Acceptance Criteria

- [ ] Entering a page URL lists discovered feed candidates (or the single feed
      if the URL already serves one).
- [ ] Selecting a candidate subscribes via `subscribe_feed` and the feed appears
      in the list.
- [ ] Empty (no candidates) and network-error states are handled gracefully.
- [ ] `flutter analyze` green (no new Rust changes expected).

## Out of Scope

- Backend discovery logic (P1a `discover_feeds` / `discover_feed_links`)
- OPML import (P3a) / special-feed subscribe-by-id (P3c)
- Auto-suggesting feeds from browsing history (future)

## Technical Notes

- Backend already in place: `rust/src/api/feed.rs::discover_feeds`,
  `rust/src/feed/discover.rs::discover_feed_links` (scraper-based).
- Livo discovery panel reference: `doc/Livo/src/renderer/` discover UI +
  `src/main/handlers/discover*` (see parent `research/`).
