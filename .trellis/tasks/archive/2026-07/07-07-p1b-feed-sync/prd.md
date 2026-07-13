# P1b: Feed sync & refresh with progress streaming

**Parent**: `07-07-livo-frb-refactor` · **Depends on**: P1a

## Goal

Port Livo's feed refresh. `sync_feeds` async fn + `StreamSink<SyncProgress>`,
fetch all/selected feeds, parse, upsert entries (idempotent), simhash near-dup
dedup (in-memory, parity with Livo), emit per-feed progress. Manual + periodic
refresh.

## Scope (in)

- `rust/src/feed/sync.rs`:
  - `sync_feeds(sink: StreamSink<SyncProgress>, feed_ids: Vec<String>)` —
    fetch + parse each, upsert entries, emit `SyncProgress` (mirror Livo's
    `FeedRefreshProgressPayload`: total, completed, feed_id, new_entries, done).
  - Idempotent upsert (by guid → fallback url; no duplicate entries on re-run).
  - Simhash dedup: port `doc/Livo/src/main/database/entry-simhash.ts` — 64-bit
    fingerprint, SHA-1 per token (unigram+bigram+trigram), Hamming distance ≤ 9,
    LRU cache 8192. **In-memory only** (parity with Livo; persisted fingerprints
    are a future option).
- `rust/src/api/feed.rs` — expose `sync_feeds` / `refresh_all` / `refresh_feed`.
- Flutter: refresh button + progress UI consuming the `StreamSink`; unread
  counts update on completion.

## Acceptance Criteria

- [ ] Refresh fetches + upserts entries; re-running is idempotent (no dup entries)
- [ ] Near-duplicate entries deduped (simhash Hamming ≤ 9) within a feed
- [ ] `StreamSink` emits per-feed progress; Dart UI reflects total/completed/new
- [ ] Network/parse failures per-feed don't abort the whole sync (partial success + error report)
- [ ] `cargo test` (simhash + dedup + idempotent-upsert unit tests) + `flutter analyze` green

## Out of Scope

- Entry reading UI (P2a) · search (P2b) · scheduled background sync (future)
- persisted simhash column (future) · FTS5 (future)

## Technical Notes

- Research: `research/frb-bridge-design.md` §2 (StreamSink canonical signature);
  `research/rust-sqlite-binding.md` (simhash is in-memory, not persisted)
- Livo: `doc/Livo/src/main/database/entry-simhash.ts`, `src/main/services/feed/`,
  `src/shared/renderer-events.ts` (`FeedRefreshProgressPayload`)
- Verify `StreamSink<T>` end-to-end with a trivial smoke fn first (no in-repo
  stream fn exists yet — see frb-bridge-design.md caveat)
