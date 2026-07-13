# P2b: Full-text entry search

**Parent**: `07-07-livo-frb-refactor` · **Depends on**: P2a

## Goal

Port Livo's entry search. `search_entries(query)` (LIKE-based, parity with Livo
for MVP) + Flutter quick-search UI. FTS5 noted as a future enhancement.

## Scope (in)

- `rust/src/api/entry.rs` — `search_entries(query, feed_id?)` → `Vec<EntryListItem>`,
  `LIKE %query%` on title + summary + content (parity with Livo
  `entry-repository.searchEntries`). Case-insensitive.
- Flutter: quick-search box + results list; selecting a result opens the entry
  detail (reuses P2a detail view).

## Acceptance Criteria

- [ ] Search returns matching entries across all feeds (or within a feed)
- [ ] Results open in the detail view (P2a)
- [ ] Empty/degenerate queries handled gracefully (no results state)
- [ ] `cargo test` (search unit test w/ seeded entries) + `flutter analyze` green

## Out of Scope

- FTS5 / ranked relevance (future enhancement) · saved searches (future)
- search history (future)

## Technical Notes

- Livo: `doc/Livo/src/main/database/repositories/entry-repository.ts`
  (`searchEntries` uses `LIKE`, not FTS)
- FTS5 is available by default with rusqlite `bundled` (see
  `research/rust-sqlite-binding.md`); adopting it later = a new migration +
  `entries_fts` virtual table + triggers — not required for MVP parity.
