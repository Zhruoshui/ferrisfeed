# P0b: SQLite persistence layer & schema migration

**Parent**: `07-07-livo-frb-refactor` · **Depends on**: P0a

## Goal

Land `rusqlite` (bundled) persistence with schema migrations + repositories for
Feed/Entry/Category, opened in `init_app()`, with CRUD exposed over FRB. Data
now persists across launches. The legacy `reader.rs` JSON-snapshot prototype
stays compiling until P1a removes it (see scope note) — avoids throwaway
Flutter stubs in P0b.

## Scope (in)

- `rust/Cargo.toml`: add `rusqlite` (`bundled`), `rusqlite_migration`,
  `parking_lot`.
- `rust/src/db/`:
  - `connection.rs` — `Mutex<Connection>` in `OnceLock`; `init_db(path)` opens
    with `WAL` + `foreign_keys=ON` + `synchronous=NORMAL` (mirrors Livo
    `sqlite-adapter.ts`).
  - `migrations/` — port the **MVP subset** of Livo's `sqlite-schema.ts`
    migrations: `feeds`, `entries`, `categories` (+ indexes). Skip
    `fever_*`, `ai_*`, `sync_changes` tables (out of MVP scope).
  - `repositories/{feed,entry,category}.rs` — port `row-mappers.ts` →
    `query_map` closures; CRUD methods.
- `rust/src/api/app.rs` — `init_app()` calls `init_db(path)` with a path
  obtained from Flutter (`getApplicationDocumentsDirectory()`).
- `rust/src/api/{feed,entry}.rs` — expose CRUD as plain `fn` (worker pool) or
  `async fn` + `spawn_blocking_with` per the bridge policy.
- **Keep `rust/src/api/reader.rs` compiling** (defer removal to P1a — P1a
  rewires the Flutter feed UI off the snapshot APIs, so removing it there avoids
  throwaway Flutter stubs in P0b). The new `feed.rs`/`entry.rs` APIs coexist
  with `reader.rs` until P1a.
- Minimal Flutter: pass DB path into `init_app`; app still builds (UI rewire is
  P1a/P2a).
- Rewrite `.trellis/spec/backend/database-guidelines.md` for rusqlite (replace
  the JSON-snapshot doc).

## Acceptance Criteria

- [ ] DB opens on app start; migrations run on fresh install + idempotent on rerun
- [ ] Feed / Entry / Category CRUD round-trips through FRB to Dart
- [ ] WAL/FK pragmas set; FK constraints enforced (e.g. entry.feed_id → feeds)
- [ ] `cargo test` (repo unit tests w/ temp DB) + `flutter analyze` green
- [ ] `database-guidelines.md` rewritten (Migrations + Query Patterns filled)

## Out of Scope

- Feed fetch/parse/sync (P1a/P1b) · entry reading UI (P2a) · FTS5 (enhancement)
- simhash dedup (P1b) · persisted simhash column (future)

## Technical Notes

- Research: `research/rust-sqlite-binding.md` (recommended setup, connection
  pattern, migration choice, Android caveat)
- Livo schema: `doc/Livo/src/main/database/{sqlite-schema,indexes,row-mappers,sqlite-adapter}.ts`
- Livo stores `media`/`source_entry_ids` as JSON-in-TEXT (decode via `serde_json`);
  dates as epoch-ms INTEGER (use `chrono` `from_timestamp_millis`, no rusqlite/chrono feature)
