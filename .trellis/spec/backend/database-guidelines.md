# Database Guidelines

> SQLite persistence patterns and conventions for the Rust side of the app.

---

## Overview

Reader state (feeds, entries, categories) is persisted in a SQLite database
managed from Rust via [`rusqlite`](https://crates.io/crates/rusqlite) (with the
`bundled` feature, which compiles SQLite from C source so the same build works
on android/ios/linux/macos/windows with FTS5/JSON1/RTREE enabled). Migrations
are tracked by `PRAGMA user_version` through
[`rusqlite_migration`](https://crates.io/crates/rusqlite_migration).

This replaced the throwaway JSON-snapshot prototype in `api/reader.rs` (which is
still kept compiling until P1a rewires the Flutter UI off it). The legacy
`ReaderSnapshot` approach is gone for new code; do not add new persistence on
top of it.

---

## Connection pattern

A single `Connection` lives behind a `parking_lot::Mutex` inside a
`std::sync::OnceLock`, initialized once at app startup. `rusqlite::Connection`
is `Send` but `!Sync`, so `Mutex<Connection>` is the canonical shared-state
shape.

```rust
// rust/src/db/connection.rs
static DB: OnceLock<Mutex<Connection>> = OnceLock::new();

pub fn init_db(path: &str) -> Result<(), AppError> {
    let mut conn = Connection::open(path)?;
    conn.pragma_update(None, "journal_mode", "WAL")?;
    conn.pragma_update(None, "foreign_keys", "ON")?;
    conn.pragma_update(None, "synchronous", "NORMAL")?;
    migrations::run(&mut conn)?;
    DB.set(Mutex::new(conn))
        .map_err(|_| AppError::database("database already initialized"))?;
    Ok(())
}

pub fn with_db<F, R>(f: F) -> Result<R, AppError>
where F: FnOnce(&Connection) -> Result<R, AppError> {
    let guard = DB.get().ok_or_else(|| AppError::database("..."))?.lock();
    f(&*guard)
}
```

Rules:

- **Open once.** `init_db` is called from `api::app::init_database` (a plain
  `pub fn` on the FRB worker pool), which Dart invokes after `RustLib.init()`
  with a path from `getApplicationDocumentsDirectory()`. It must not be called
  twice (the `OnceLock::set` returns an error).
- **Borrow, don't store.** API functions borrow the connection via `with_db`.
  The lock is held only for the duration of a single short query and is never
  held across an `.await` point.
- **Threading.** API functions that touch the DB are plain `pub fn` (no
  `#[frb(sync)]`) so they run on the FRB worker thread pool and return a
  `Future` to Dart — the Flutter UI is never blocked. See
  `directory-structure.md` → "Sync vs async policy". For async composition
  (HTTP fetch → DB write, in P1a), use `async fn` +
  `flutter_rust_bridge::spawn_blocking_with` for the DB touch.
- **Tests** do not use the global `OnceLock`; they build a fresh
  `Connection::open_in_memory()` (or a temp file), call `migrations::run`, and
  pass `&Connection` directly to repository functions.

---

## Migrations

Migrations live in `rust/src/db/migrations.rs` as a `Migrations::new(vec![M::up(SQL)])`
list. `rusqlite_migration` tracks applied state via SQLite's `PRAGMA user_version`
(an integer) — there is **no `schema_migrations` table** (unlike Livo's TS
adapter). Apply with `migrations.to_latest(&mut conn)`.

Conventions:

- **One SQL string per migration**, inline as a `const &str` (multiple
  statements separated by `;` are fine — `rusqlite_migration` runs them via
  `execute_batch`). `include_str!` from `rust/migrations/*.sql` is also
  acceptable for larger migrations.
- **Idempotent DDL.** Use `CREATE TABLE IF NOT EXISTS` / `CREATE INDEX IF NOT
  EXISTS` so re-running on an already-current DB is a no-op (the
  `migrations_are_idempotent` test guards this).
- **Add a new migration, never edit an applied one.** Bump `user_version` by
  appending a new `M::up(...)` entry. Editing an already-applied migration has
  no effect on existing DBs (the version is already recorded) and breaks
  reproducibility.
- The MVP schema (`v1`) ports only `feeds`, `entries`, `categories` (+ indexes)
  from Livo's `sqlite-schema.ts`. `fever_*`, `ai_*`, `sync_changes`,
  `entry_ai_*` tables are intentionally out of scope.

---

## Query patterns

Repositories are free functions in `rust/src/db/repositories/*.rs`, each taking
a `&Connection`. They use `prepare` / `query_map` / `execute` with the
`params![]` macro. Row mappers are closures (or `fn(&Row) -> Result<T,
rusqlite::Error>`) passed to `query_map`, porting Livo's `row-mappers.ts`.

```rust
pub fn list_feeds(conn: &Connection) -> Result<Vec<Feed>, AppError> {
    let mut stmt = conn.prepare("SELECT * FROM feeds ORDER BY title COLLATE NOCASE")?;
    let rows = stmt.query_map([], feed_from_row)?;
    Ok(rows.collect::<Result<Vec<_>, _>>()?)
}

fn feed_from_row(row: &Row) -> Result<Feed, rusqlite::Error> {
    Ok(Feed { id: row.get("id")?, title: row.get("title")?, /* ... */ })
}
```

- **Named or positional?** Positional `?N` / `params![]` is the default. Use
  `?N IS NULL OR col = ?N` to make an optional filter parameter nullable
  (binding `None` disables the filter).
- **Booleans** are stored as `INTEGER` `0`/`1`; map with
  `row.get::<_, i64>("is_read")? != 0` and bind `is_read as i64`.
- **Upserts** use `INSERT ... ON CONFLICT(id) DO UPDATE SET ...`. To preserve a
  created-at-style column on update, simply omit it from the `DO UPDATE SET`
  clause (it keeps its existing value).
- **Dedup** by checking existence before insert (e.g. `upsert_entries` skips
  drafts whose `url` already exists for the feed), mirroring Livo's snapshot
  prototype. Do not add `UNIQUE` constraints that Livo does not have.
- **Denormalized counts** (`feeds.article_count`, `feeds.unread_count`) are
  recomputed via `recompute_feed_counts` after entry mutations, matching Livo's
  `recalculate_feed_counts`.

---

## Data type mapping

| Rust (DTO)                     | SQLite column            | Notes |
|--------------------------------|--------------------------|-------|
| `String`                       | `TEXT`                   | |
| `Option<String>`               | `TEXT` (nullable)        | bind `None` → `NULL` |
| `bool`                         | `INTEGER` (`0`/`1`)      | |
| `i32` / `i64`                  | `INTEGER`                | |
| `DateTime<Utc>`                | `INTEGER` epoch-millis   | `DateTime::from_timestamp_millis` / `.timestamp_millis()`. **Do not** enable the `rusqlite/chrono` feature — store epoch-ms integers like Livo. |
| JSON payloads (`media`, ...)   | `TEXT` (JSON-in-TEXT)    | decode with `serde_json::from_str`; the `From<serde_json::Error> for AppError` impl maps decode failures to `AppError::Database`. |

---

## Pragmas & foreign keys

Set in `init_db` (mirrors Livo `sqlite-adapter.ts`):

- `journal_mode = WAL` — concurrent readers + one writer. (WAL is not supported
  for `:memory:` DBs; tests that use `open_in_memory` skip this pragma.)
- `foreign_keys = ON` — FK constraints are enforced. `entries.feed_id`
  references `feeds(id) ON DELETE CASCADE`, so deleting a feed removes its
  entries. Inserting an entry with an unknown `feed_id` raises
  `SQLITE_CONSTRAINT_FOREIGNKEY` → `AppError::Database`.
- `synchronous = NORMAL` — safe under WAL, faster than `FULL`.

---

## Error handling

All repository functions return `Result<T, AppError>`. `rusqlite::Error`,
`std::io::Error`, and `serde_json::Error` convert to `AppError` via `From` impls
defined in `rust/src/db/connection.rs` (kept out of `api/error.rs` so FRB
codegen never sees `rusqlite` types). `?` propagates naturally:

- Missing row on a mutation → `AppError::not_found("entry", id)` (checked via
  `rows_affected == 0`).
- FK/unique/other SQLite failure → `AppError::Database(msg)`.
- Anyhow stays internal-only and must not cross the FRB boundary.

See `error-handling.md` for the full `AppError` contract.

---

## Naming conventions

- Table names: `snake_case`, plural (`feeds`, `entries`, `categories`).
- Column names: `snake_case` (`source_url`, `published_at`, `is_read`).
- Index names: `<table>_<cols>_idx` (`entries_feed_published_idx`), mirroring Livo.
- DTO field names are `snake_case` in Rust; FRB converts to `camelCase` in Dart.

---

## Common mistakes

- **Exposing `types::Feed` while `reader.rs` exists.** FRB generates one Dart
  class per Rust struct *name* and imports every `api/` module into
  `frb_generated.dart`, so two `Feed` structs produce a duplicate-identifier
  clash. The persisted feed API reuses `reader::Feed` until P1a removes
  `reader.rs`; `types::Feed`/`ArticleViewMode`/`FeedDraft` stay
  un-`#[frb(unignore)]`d.
- **Holding the `Mutex` across an `.await`.** `with_db` locks and unlocks
  synchronously; never `.await` while holding the guard. For HTTP-then-DB flows,
  do the async work first, then `spawn_blocking_with` the DB call.
- **Using `#[frb(sync)]` for DB work.** Sync functions run on the Dart UI
  isolate and block it. DB access must be plain `pub fn` (worker pool) or
  `async fn` + `spawn_blocking_with`.
- **The old `#[serde(default)]` rule no longer applies to persisted data.** It
  was a JSON-snapshot migration hack. New SQLite columns default at the DB level
  (`DEFAULT 0`, etc.); schema changes are real migrations.
