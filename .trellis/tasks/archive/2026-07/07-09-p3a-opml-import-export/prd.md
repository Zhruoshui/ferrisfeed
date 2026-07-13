# P3a: OPML import/export

**Parent**: `07-09-p3-discovery-special-feeds` · **Depends on**: -

## Goal

Port Livo's OPML import/export. Parse OPML 2.0 on import and batch-subscribe to
each outline's `xmlUrl`; serialize the current feed list to OPML 2.0 on export.
Uses the Rust `opml` crate (see parent ADR + `research/opml-crate-selection.md`).

## Scope (in)

- `rust/src/api/feed.rs` (or a new `api/opml.rs`): `import_opml(xml: String) ->
  ImportReport` (async) - parse OPML, iterate `<outline xmlUrl=...>`, call
  `subscribe_feed_impl` per entry (idempotent on `source_url`), collect
  successes/failures; honor folder/category nesting as `feed.folder` /
  `feed.category`.
- `export_opml() -> String` - serialize `list_feeds()` into an OPML 2.0
  `<outline>` tree (folders -> nested outlines).
- Flutter: import (file picker -> `import_opml`) + export (`export_opml` -> save
  file) entry points in the feed management UI.

## Acceptance Criteria

- [ ] Importing a valid OPML subscribes to all `xmlUrl` outlines (deduped via
      `source_url`); nested folders map to `feed.folder`.
- [ ] Per-feed import failures are isolated (one bad URL doesn't abort the rest)
      and reported.
- [ ] Export produces OPML 2.0-valid XML re-importable by another reader.
- [ ] `cargo test` (parse/serialize + import round-trip) + `flutter analyze` +
      `bash scripts/frb.sh` green.

## Out of Scope

- OPML 1.0 / non-RSS outlines (the `opml` crate targets 2.0)
- RSSHub / special-feed outlines (they are normal `xmlUrl`s once subscribed)
- Merge / conflict policy beyond `source_url` dedup (deferred)

## Technical Notes

- Crate: `opml` v1.1.6 (parse + serialize) - confirm API + pure-Rust + MSRV at
  implementation time.
- Reuse `subscribe_feed_impl` (idempotent on `source_url`).
- Livo OPML field-mapping + merge semantics: see parent `research/` (pending
  subagent) - `doc/Livo/` OPML handler.
- FRB codegen (`bash scripts/frb.sh`) after adding `import_opml` / `export_opml`
  to `api/`.
