# Research: Rust SQLite binding for Flutter + FRB (Livo port)

- **Query**: Which Rust SQLite binding to use for a Flutter + flutter_rust_bridge cross-platform app (android/ios/linux/macos/windows)? Compare rusqlite (+refinery/rusqlite_migration) vs sqlx vs sea-orm/drift-style; evaluate threading & FRB interop, migrations, cross-platform mobile, FTS5, simhash dedup; recommend one.
- **Scope**: mixed (internal Livo source + current repo; external crate docs, FRB source/issues)
- **Date**: 2026-07-07

## TL;DR Recommendation

**Use `rusqlite` with the `bundled` feature + `rusqlite_migration` (or `refinery` if you prefer a `schema_migrations`-style table). Hold one `Connection` behind a `Mutex` (parking_lot or std), initialized once. Expose DB-touching operations as plain `fn` (NOT `#[frb(sync)]`) so they run on FRB's worker thread pool, or as `async fn` that delegates to `flutter_rust_bridge::spawn_blocking_with` when composing DB writes with async work (e.g. HTTP fetch → persist).**

Rationale (detailed below): rusqlite+bundled is a near-1:1 match for Livo's synchronous better-sqlite3 design (same single-connection, same WAL/FK pragmas, same migration-list shape), compiles an identical SQLite across all 5 target platforms with FTS5/JSON1/RTREE enabled by default, has no async-runtime coupling (so it sidesteps the `Send`-future pitfall that currently breaks sea-orm under FRB), and is the most downloaded/mature option. sqlx is a reasonable runner-up if async I/O composition or compile-time query checking becomes valuable later.

---

## Findings

### Files Found (internal — current repo state)

| File Path | Description |
|---|---|
| `rust/Cargo.toml` | Current Rust deps: `flutter_rust_bridge` (git rev `254b193`), `chrono`, `serde`, `serde_json`, `url`, `uuid`. **No SQLite, no DB, no HTTP yet.** `crate-type = ["cdylib", "staticlib"]`. |
| `rust/src/lib.rs` | `pub mod api; mod frb_generated;` — minimal. |
| `rust/src/api/mod.rs` | Exposes `simple` + `reader` modules. |
| `rust/src/api/simple.rs` | `greet()` (`#[frb(sync)]`) + `init_app()` (`#[frb(init)]`, calls `setup_default_user_utils()`). This is the natural place to initialize the DB connection on app startup. |
| `rust/src/api/reader.rs` | **Throwaway JSON-snapshot prototype** (900 lines). Every function is `#[frb(sync)]` and operates on a `snapshot_json: String` passed in from Dart. No persistence. This `#[frb(sync)]`-everywhere pattern MUST be abandoned for DB access — see threading analysis. |
| `flutter_rust_bridge.yaml` | `rust_input: crate::api`, `rust_root: rust/`, `dart_output: lib/src/rust`, `auto_upgrade_dependency: false`. |
| `doc/Livo/src/main/database/sqlite-schema.ts` | **Source schema to port.** 9 numbered migrations (v1 `init` … v9 `feed-sync-title`), tracked in a `schema_migrations(version, name, applied_at)` table. Tables: `feeds`, `entries`, `ai_digest_runs`, `fever_accounts`, `fever_feed_mappings`, `fever_item_mappings`, `fever_sync_states`, `entry_ai_summary_sessions`, `entry_ai_translation_sessions`, `sync_changes`. `entries` has ~30 columns incl. readability/AI/podcast fields. |
| `doc/Livo/src/main/database/indexes.ts` | In-memory index builders (not SQL indexes). The SQL indexes live inline in `sqlite-schema.ts` (e.g. `entries_feed_published_idx`, `entries_read_published_idx`, `entries_starred_published_idx`, `entries_published_idx`, `entries_url_idx`). |
| `doc/Livo/src/main/database/sqlite-adapter.ts` | **Pattern to mirror.** Constructor opens one `BetterSqlite3(dbPath)`, sets `journal_mode=WAL`, `foreign_keys=ON`, `synchronous=NORMAL`, runs migrations, then wires repositories that share the single connection. |
| `doc/Livo/src/main/database/row-mappers.ts` | `feedFromRow`/`entryFromRow`/etc. — column→struct mappers. Direct port target for rusqlite `query_map` closures. Note `media` and `source_entry_ids` are JSON-in-TEXT columns. |
| `doc/Livo/src/main/database/entry-simhash.ts` | **Simhash dedup is in-memory, NOT persisted.** 64-bit fingerprint, SHA-1 per token (unigram+bigram+trigram), Hamming distance ≤ 9 = near-dup, LRU cache of 8192. Runs on the read path in TS. No SQLite column stores the hash. |
| `doc/Livo/src/main/database/repositories/entry-repository.ts` | `searchEntries` uses **`LIKE %query%`** on title/content/summary — **NOT FTS5**. So FTS5 is optional for a faithful port; it would be an enhancement. |
| `.trellis/spec/backend/database-guidelines.md` | Documents the *current* JSON-snapshot approach (no DB). Migrations/Query Patterns sections are stubs ("To be filled"). Will need rewriting once a binding lands. |

### External References (crate metadata, fetched 2026-07-07)

| Crate | Latest | Total downloads | Recent (90d) | Notes |
|---|---|---|---|---|
| `rusqlite` | 0.40.1 | 78.3M | 23.6M | "Ergonomic wrapper for SQLite". Updated 2026-06-06. Maintained by `rust-db` org. |
| `sqlx` | 0.9.0 | 115.3M | 29.7M | Async, compile-time checked, supports PG/MySQL/SQLite. Updated 2026-05-21. |
| `refinery` | 0.9.2 | 8.7M | 1.9M | Migration toolkit; supports `rusqlite`, `tokio-postgres`, `mysql_async`, etc. |
| `rusqlite_migration` | 2.6.0 | 2.8M | 1.9M | "Simple schema migration library for rusqlite using `user_version` instead of an SQL table." |
| `sea-orm` | 2.0.0-rc.42 | 21.5M | 3.1M | Async ORM over sqlx. **Currently RC.** |
| `libsqlite3-sys` | (via rusqlite) | — | — | FFI bindings; `bundled` feature compiles SQLite from C source via `cc`. |

---

## Detailed Analysis

### 1. Threading model & FRB interop (the decisive factor)

FRB's default handler uses **two execution targets** (verified in `frb_rust/src/thread_pool/io.rs` and `frb_rust/src/rust_async/io.rs` at master):

| FRB function flavor | Runs on | Blocks Flutter UI? | Constraint |
|---|---|---|---|
| `#[frb(sync)] pub fn ...` | **Main isolate (main thread)** | **YES** | Must be sub-millisecond. **Never touch SQLite here.** |
| plain `pub fn ...` (no `#[frb(sync)]`) | **Worker thread pool** (`SimpleThreadPool(threadpool::ThreadPool)`) | No | Job must be `FnOnce() + Send + 'static`. Returns a `Future` to Dart. |
| `pub async fn ...` | **Tokio multi-threaded runtime** (`tokio::runtime::Runtime::new()` — multi-threaded) | No | Future must be `Future + Send + 'static`, output `Send + 'static`. |

FRB also exposes `flutter_rust_bridge::spawn_blocking_with(f, thread_pool)` → wraps `tokio::task::spawn_blocking(f)` (on non-web it uses tokio's blocking pool; the `thread_pool` arg is ignored off-web). This is the supported bridge from `async fn` to blocking rusqlite calls.

**Implication for a sync binding (rusqlite):**
- `rusqlite::Connection` is `Send` but `!Sync` (confirmed in docs.rs auto-trait impls). Therefore `Mutex<Connection>` is the canonical shared-state pattern (`Mutex<T>` only requires `T: Send`). `parking_lot::Mutex` or `std::sync::Mutex` both work; `parking_lot` is non-poisoning-free and faster.
- A plain `pub fn list_entries(...) -> Result<Vec<Entry>, DbError>` (no `#[frb(sync)]`) runs on the worker pool, locks the `Mutex<Connection>` for the duration of the query, and returns. **The Flutter UI is never blocked** because the call is already off the main isolate. This is the simplest correct pattern.
- For async composition (fetch feed over HTTP, then write entries to DB), write `pub async fn sync_feed(...)` that does the HTTP work async, then `spawn_blocking_with(move || db.lock().insert_entries(...), handler.thread_pool()).await`. This keeps the lock held only on the blocking pool, not across `.await` points (which would deadlock or require `Send` guards).
- **Connection-per-task vs single Mutex**: Livo uses a single shared connection (better-sqlite3 is synchronous, one `Database` object shared by repositories). The faithful port is one `Mutex<Connection>`. With WAL mode, SQLite allows concurrent readers + one writer, so a read pool (e.g. `r2d2-sqlite`) could improve read throughput under contention — but for a local single-user RSS reader this is premature; one connection behind a Mutex matches Livo and is simpler. If read contention shows up later, swap to `r2d2` + `r2d2_sqlite` without changing call sites.

**Implication for an async binding (sqlx):**
- Raw `sqlx::sqlite` futures ARE `Send` (sqlx is designed for multi-threaded tokio), so `pub async fn` FRB functions returning sqlx results compile and run under FRB's default runtime. Use `sqlx::sqlite::SqlitePool` (connection pool) instead of a Mutex — async pools are the idiomatic sqlx pattern.
- **However**, higher-level ORMs built on sqlx do NOT always satisfy FRB's `Send` requirement. See FRB issue **#3265** (open): `sea-orm` + `sea-schema` produces `dyn Future<Output = Result<_, sea_orm::SqlxError>>` that is `!Send`, failing `wrap_async` in `frb_generated.rs`. So **sea-orm is currently unusable with FRB** until that upstream `Send` issue is fixed. Raw sqlx is fine.
- The compile-time query checking (`sqlx::query!`) requires either a live `DATABASE_URL` at build time or running `cargo sqlx prepare` to emit an offline `.sqlx` cache. This is workable but adds CI friction during an active schema-evolving port.

**Verdict:** rusqlite is strictly simpler under FRB. The sync API maps directly onto FRB's worker thread pool with no `Send`-future hazards, no extra runtime coupling, and no offline-query-cache workflow.

### 2. Migration story

Livo's source (`sqlite-schema.ts`) uses an explicit ordered `MIGRATIONS: [{version, name, sql}]` array, tracked in a `schema_migrations(version PK, name, applied_at)` table. Two Rust options mirror this closely:

- **`rusqlite_migration`** (2.6.0): `Migrations::new(vec![M::up(sql1), M::up(sql2), ...])` then `migrations.to_latest(&mut conn)?`. Tracks state via SQLite's **`PRAGMA user_version`** (an integer), not a table. Lightest option; no extra table cluttering the schema. Trade-off: no migration `name`/`applied_at` recorded (just an integer), and it differs from Livo's `schema_migrations` table shape. Good when you don't need to query applied-migration metadata at runtime.
- **`refinery`** (0.9.2, `features = ["rusqlite"]`): embeds `.sql` files via `refinery::embed_migrations!("migrations")` or a `Migrations` struct. Tracks a **`refinery_schema_history(version, name, applied_on, checksum)`** table — closest in spirit to Livo's `schema_migrations(version, name, applied_at)`. Supports versioned + named migrations and can run sync (`Runner::run`) or async (`Runner::run_async`, needs `tokio-postgres`/`mysql_async`; for rusqlite use sync `run`). Recommended if you want to preserve Livo's named-migration auditability.
- **`sqlx::migrate!`** (sqlx `migrate` feature): embeds a `migrations/` dir of timestamped `.sql` files at compile time via the `migrate!` macro. Tracks `_sqlx_migrations` table. Clean and idiomatic for sqlx users, but couples migration choice to the sqlx decision. `sqlx migrate add/run/revert` CLI exists.

For a 1:1 port of Livo's 9 migrations, **refinery** gives the closest shape (named, versioned, history table) but rusqlite_migration is fine if `user_version` suffices. Either way, the migration SQL from `sqlite-schema.ts` ports verbatim (it's portable SQLite DDL).

### 3. Cross-platform constraints (mobile + desktop)

- **`bundled` feature compiles SQLite from C source** via `libsqlite3-sys` + the `cc` crate. This produces a **statically-linked, identical SQLite build across android/ios/linux/macos/windows** — no system-library dependency, no "wrong SQLite version on platform X" surprises. This is exactly what `better-sqlite3` does in Electron (it also bundles SQLite source), so behavioral parity with Livo is high.
- **FTS5 is enabled by default in the bundled build** (verified in `libsqlite3-sys/build.rs`: `-DSQLITE_ENABLE_FTS5`, plus `FTS3`, `JSON1`, `RTREE`, `STAT4`, `DBSTAT_VTAB`, `API_ARMOR`, `COLUMN_METADATA`, `UNLOCK_NOTIFY`). So `CREATE VIRTUAL TABLE entries_fts USING fts5(...)` works out of the box if/when we adopt FTS. (Livo currently uses `LIKE`, so FTS5 is an enhancement, not a port requirement.)
- **sqlx `sqlite` feature** also bundles (`sqlite-bundled`) — same underlying `libsqlite3-sys`. So cross-platform SQLite availability is equivalent for rusqlite and sqlx.
- **Android x86_64 emulator caveat (applies to BOTH rusqlite and sqlx):** FRB issues **#1719** and **#1844** report `dlopen failed: cannot locate symbol "__extenddftf2"` on Android x86_64 emulator when the Rust lib links bundled SQLite. This is a **clang_rt builtins linking gap**, not an FRB or rusqlite bug. It affects emulators only; real arm/arm64 devices work. The documented fix (issue #1719, comment by `mike-lloyd03`) is a `build.rs` that links `clang_rt.builtins-x86_64-android` for `x86_64`-android targets:
  ```rust
  // build.rs
  fn main() {
      let target_arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap();
      let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap();
      if target_arch == "x86_64" && target_os == "android" {
          let android_home = std::env::var("ANDROID_HOME").expect("ANDROID_HOME not set");
          println!("cargo:rustc-link-search={android_home}/ndk/26.1.10909125/toolchains/llvm/prebuilt/linux-x86_64/lib/clang/17/lib/linux/");
          println!("cargo:rustc-link-lib=static=clang_rt.builtins-x86_64-android");
      }
  }
  ```
  Adjust the NDK version path to match the installed NDK. This is a one-time setup cost for any bundled-SQLite choice.
- **iOS**: rusqlite `bundled` compiles cleanly for `aarch64-apple-ios` and the iOS simulator (`x86_64`/`aarch64-apple-ios-sim`). No special flags needed. (Mozilla `application-services` ships rusqlite-based components on iOS — strong precedent.)
- **WASM / web**: Web was dropped (recent commits). Neither rusqlite nor sqlx target `wasm32-unknown-unknown` for SQLite (no filesystem). Out of scope. The leftover `rust/target/wasm32-unknown-unknown/` build artifacts in the repo are stale and can be ignored/deleted.
- **`crate-type = ["cdylib", "staticlib"]`** in `rust/Cargo.toml` is already correct for FRB on all targets; rusqlite `bundled` adds only a build-time C compile step via `cc`, no crate-type change needed.

### 4. Maturity / ecosystem / maintenance

- **rusqlite**: 78M downloads, `rust-db` org (also maintains `r2d2`, `r2d2-sqlite`, `refinery`). Active, releases every few months. Used by Mozilla application-services (Logins/Places/Nimbus on iOS+Android), Matrix SDK, and many desktop apps. Strong mobile precedent.
- **sqlx**: 115M downloads, very active. Compile-time checking is a genuine productivity feature for stable schemas, but during an active port where the schema is still being ported migration-by-migration, the offline-cache workflow (`sqlx prepare`) is friction.
- **refinery**: 8.7M downloads, same `rust-db` org as rusqlite — first-class rusqlite integration.
- **rusqlite_migration**: 2.8M downloads, smaller but focused; uses `user_version` (simplest possible).
- **sea-orm**: 2.0.0 is still **RC**; and issue #3265 shows it breaks FRB codegen today. Not recommended.

### 5. Suitability for Livo's data model

- **Feed / Entry / Category tables**: rusqlite's `prepare`/`query_map`/`execute` map 1:1 onto Livo's `db.prepare(...).run/all` better-sqlite3 calls. The `row-mappers.ts` functions become closures passed to `query_map`. `media`/`source_entry_ids` JSON-in-TEXT columns decode via `serde_json::from_str` (already a dep). `chrono` (already a dep) maps to `INTEGER` epoch-ms columns via `DateTime::from_timestamp_millis` — no `rusqlite/chrono` feature needed, but enabling it gives `FromSql`/`ToSql` for `DateTime<Utc>` if you prefer storing RFC3339. Livo stores epoch-ms integers, so keep that and avoid the feature.
- **FTS5**: available by default with `bundled` (see above). If/when we move off `LIKE %q%`, create `entries_fts USING fts5(title, summary, content, content=entries, content_rowid=rowid)` + triggers. Not required for MVP parity.
- **Simhash near-dup dedup**: Livo computes fingerprints **in memory on the read path** (`entry-simhash.ts`), with an LRU cache keyed by entry id + content-lengths. Nothing is persisted in SQLite. For the Rust port, the same approach works: compute the 64-bit simhash in Rust (cheap, `sha1` crate or `ring`), compare with `popcount(a ^ b) <= 9` over candidate entries fetched from the DB. **If we later want to persist fingerprints** for cross-session dedup, add an `entries.simhash BLOB` (8 bytes) column in a new migration and compute on insert. rusqlite handles `BLOB` via `Vec<u8>`/`&[u8]` `ToSql`/`FromSql` natively. This is a future enhancement, not a port requirement — keep parity with Livo's in-memory approach for now.

---

## Recommended Setup (concrete)

### `rust/Cargo.toml` additions
```toml
[dependencies]
# ... existing ...
rusqlite = { version = "0.40", features = ["bundled"] }   # bundled = static SQLite w/ FTS5,JSON1,RTREE on all platforms
rusqlite_migration = "2.6"   # OR: refinery = { version = "0.9", features = ["rusqlite"] }
parking_lot = "0.12"          # Mutex<Connection>; lighter than std::sync::Mutex
# optional, if read-pool needed later: r2d2 = "0.8", r2d2_sqlite = "0.25"
```
Note: `uuid` currently has the `js` feature (for the old WASM prototype). With web dropped, `js` can be removed; keep `v4`+`serde`.

### Connection / init pattern
```rust
// rust/src/api/db.rs
use parking_lot::Mutex;
use rusqlite::Connection;
use std::sync::OnceLock;

static DB: OnceLock<Mutex<Connection>> = OnceLock::new();

pub fn init_db(path: &str) -> Result<(), rusqlite::Error> {
    let conn = Connection::open(path)?;
    conn.pragma_update(None, "journal_mode", "WAL")?;       // mirror Livo sqlite-adapter.ts:60
    conn.pragma_update(None, "foreign_keys", "ON")?;        // :61
    conn.pragma_update(None, "synchronous", "NORMAL")?;     // :62
    rusqlite_migration::Migrations::new(vec![
        M::up(include_str!("../migrations/v1_init.sql")),
        // ... v2..v9, ported from sqlite-schema.ts
    ]).to_latest(&mut conn)?;
    DB.set(Mutex::new(conn)).ok();  // initialized once in init_app()
    Ok(())
}
```
Call `init_db(...)` from the existing `init_app()` in `simple.rs` (or a new `#[frb(init)]` fn), passing a platform-appropriate path obtained from Flutter (e.g. `getApplicationDocumentsDirectory()` → passed in via FRB).

### FRB function shape (CRITICAL — do not copy reader.rs's `#[frb(sync)]` pattern)
```rust
// Plain fn (no #[frb(sync)]): runs on FRB worker thread pool. UI never blocks.
pub fn list_entries(feed_id: Option<String>, unread_only: bool) -> Result<Vec<Entry>, DbError> {
    let db = DB.get().expect("db not initialized");
    let conn = db.lock();   // short-lived lock, released at end of fn
    let mut stmt = conn.prepare("SELECT * FROM entries WHERE ...")?;
    let rows = stmt.query_map(params![feed_id], entry_from_row)?;
    Ok(rows.collect::<Result<Vec<_>,_>>())
}

// Async fn composing HTTP + DB: use spawn_blocking_with for the DB touch
pub async fn sync_feed(feed_id: String) -> Result<SyncReport, ReaderError> {
    let xml = fetch_feed(&feed_id).await?;          // async HTTP
    let tp = flutter_rust_bridge::for_generated::thread_pool_or_default();
    flutter_rust_bridge::spawn_blocking_with(move || {
        let db = DB.get().expect("db").lock();
        db.insert_entries(parse(xml))
    }, tp).await
}
```

### Migration files
Port Livo's `MIGRATIONS` array (`doc/Livo/src/main/database/sqlite-schema.ts`) into individual `rust/migrations/vN_name.sql` files (one per migration) and `include_str!` them, or use `refinery::embed_migrations!("migrations")` if you pick refinery. The DDL is portable SQLite verbatim.

---

## Caveats / Not Found

- **`rusqlite_migration` source README** returned 404 on the `cljoly/rusqlite-migration` repo at `master`/`main` (repo may have moved or changed default branch); the crates.io description and docs.rs confirm the `user_version`-based design, but I could not cite the exact API line. Verify against docs.rs when integrating.
- **Android x86_64 emulator `__extenddftf2` fix**: the `build.rs` snippet is quoted from FRB issue #1719 (user `mike-lloyd03`, adapted from a uniffi project). The NDK version path (`26.1.10909125`) and clang version (`17`) must match the local NDK install; validate on the project's actual NDK before relying on it. This affects emulators only — physical arm64 devices build and run without it.
- **sqlx + FRB raw (non-sea-orm) `Send` compatibility**: I confirmed sqlx futures are `Send` by design and FRB's default runtime is multi-threaded tokio (`Runtime::new()`). I did not build a sqlx+FRB toy to empirically confirm end-to-end codegen, but no open FRB issue reports raw sqlx failing (the open #3265 is sea-orm/sea-schema specific). Treat sqlx as a viable fallback, not a proven path.
- **CodeGraph index** exists at `.codegraph/` but the current Rust crate is tiny (3 api files) and has no DB code yet, so it offered nothing for this question. It will be useful post-implementation for navigating the new repository layer.
- **r2d2 read pool**: not needed for MVP; mentioned only as a future option if read contention appears. Do not add prematurely.
