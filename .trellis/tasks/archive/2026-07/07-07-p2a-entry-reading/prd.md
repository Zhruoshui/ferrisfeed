# P2a: Entry reading UI (list, read/unread, star, detail)

**Parent**: `07-07-livo-frb-refactor` · **Depends on**: P1b

## Goal

Port Livo's entry reading experience. Entry list (linear, by feed/all,
unread/starred filter, pagination), mark read/unread, toggle star, prev/next
navigation, detail view rendering HTML via `flutter_widget_from_html`.

## Scope (in)

- `rust/src/api/entry.rs`:
  - `list_entries(feed_id?, unread_only, starred_only, page)` — paginated,
    returns `EntryListItem`.
  - `get_entry(id)`, `mark_entry_read(id, read)`, `toggle_entry_star(id)`.
  - `get_adjacent_entries(id)` — prev/next within the current filter context.
- Flutter: rewire reading UI against the **persisted** model:
  - `reader_app.dart` / `reader_controller.dart` / `reader_repository.dart` /
    `article_detail_view.dart` — replace JSON-snapshot wiring with the new FRB
    entry api.
  - Linear entry list; read-on-open; star toggle; prev/next navigation.
  - Detail view renders `content` HTML via `flutter_widget_from_html`.
- Read-state sync between list and detail views.
- **Remove `rust/src/api/reader.rs`** — the last consumer. P1a/P1b kept it
  compiling because the entry reading UI still used its snapshot APIs; P2a
  rewires that UI to the persisted entry APIs, so `reader.rs` is finally
  deleted (its 10 snapshot tests + `ReaderError` go away; delete the stale
  generated `lib/src/rust/api/reader.dart` too). **Switch `api/feed.rs`** +
  `db/repositories/feed.rs` from `reader::Feed`/`ArticleViewMode` to
  `types::Feed`/`ArticleViewMode` — with `reader.rs` gone, the FRB
  duplicate-identifier clash resolves, so `#[frb(unignore)]` `types::Feed`/
  `ArticleViewMode`/`FeedDraft` and drop the `reader::Feed` reuse. Remove the
  snapshot-blob handling from `reader_repository.dart`.

## Acceptance Criteria

- [ ] Entry list shows synced entries; filter by feed / unread-only / starred-only; pagination works
- [ ] Opening an entry marks it read; unread count decrements
- [ ] Star toggle persists; detail view renders HTML content (images/links)
- [ ] Prev/next navigation moves through entries in the current filter
- [ ] `flutter analyze` + `cargo test` (entry api unit tests) green

## Out of Scope

- Search (P2b) · grid/social/wide layouts (future) · readability full-text
  extraction (future — MVP renders feed content) · reading-activity heatmap
  (P6) · keyboard shortcuts (P6)

## Technical Notes

- Livo UI reference: `doc/Livo/src/renderer/src/components/entry/` (linear
  layout, entry-content, entry-list)
- Livo entry api: `doc/Livo/src/main/handlers/entry-handlers.ts`,
  `src/main/database/repositories/entry-repository.ts`
- Current Flutter (to rewire): `lib/src/app/{reader_app,reader_controller,reader_repository,article_detail_view}.dart`
