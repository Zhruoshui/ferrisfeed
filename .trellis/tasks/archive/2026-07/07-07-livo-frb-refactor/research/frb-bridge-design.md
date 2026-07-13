# Research: FRB Bridge Design for the Livo Port

- **Query**: FRB design patterns (sync/async, streaming, errors, codegen, modules, init) for a Flutter+Rust+SQLite RSS app porting Livo's IPC layer
- **Scope**: internal scaffold + Livo contracts + FRB v2.12.0 generated-code evidence
- **Date**: 2026-07-07
- **FRB version**: 2.12.0, pinned to git rev `254b193` (confirmed in `rust/Cargo.toml`, `pubspec.yaml`, `rust/src/frb_generated.rs` stamp)

## Verified facts about the current scaffold

| File | Role |
|---|---|
| `rust/src/api/mod.rs` | declares `pub mod simple; pub mod reader;` |
| `rust/src/api/simple.rs` | `greet()` (`#[frb(sync)]`) + `init_app()` (`#[frb(init)]`) |
| `rust/src/api/reader.rs` | JSON-snapshot prototype; mostly `#[frb(sync)]` except `import_feed_from_xml` (`async fn`); `ReaderError` is a struct `{code,message}` |
| `flutter_rust_bridge.yaml` | `rust_input: crate::api`, `rust_root: rust/`, `dart_output: lib/src/rust`, `auto_upgrade_dependency: false` |
| `lib/src/rust/frb_generated.dart` | `RustLib.init()` / `dispose()`; `executeRustInitializers()` calls `init_app` |
| `lib/src/app/reader_repository.dart` | currently does HTTP fetch in **Dart** (`http.Client`) then passes XML to Rust — refactor moves this to Rust |

## 1. Sync vs async

- `#[frb(sync)]` → runs on the **Dart main isolate (UI thread)** and blocks it until it returns. Dart binding returns a plain value, not a Future.
- plain `async fn` (with `#[frb]`) → runs the Rust body on the FRB/Rust thread pool; Dart returns `Future<T>`.
- `#[frb(init)]` → awaited inside `RustLib.executeRustInitializers()`.

**Recommendation — async by default; `#[frb(sync)]` only for tiny pure/indexed lookups** (defaults, single indexed PK lookups <1ms, `mark_read`/`toggle_star`). Never do network or multi-row DB work in a sync fn. **Critical for rusqlite**: rusqlite is blocking — wrap it in `async fn` + `tokio::task::spawn_blocking` so it stays off the UI isolate.

## 2. Streaming events Rust→Dart (StreamSink)

Codec already wired: `default_stream_sink_codec = SseCodec`. Canonical push stream:

```rust
#[flutter_rust_bridge::frb]
pub fn sync_feeds(sink: StreamSink<SyncProgress>, feed_ids: Vec<String>) {
    for (i, id) in feed_ids.iter().enumerate() {
        // fetch + parse + persist ...
        sink.add(SyncProgress { total: feed_ids.len(), completed: i + 1, feed_id: id.clone(), new_entries: n, done: i + 1 == feed_ids.len() });
    }
}
```
Dart: `Stream<SyncProgress> syncFeeds({required List<String> feedIds})`. Mirror Livo's `FeedRefreshProgressPayload` (`doc/Livo/src/shared/renderer-events.ts`). One stream per long op is cleaner than Livo's many discrete channels.

## 3. Error handling

- Verified: `Result<T, ReaderError>` → Dart throws `ReaderError implements FrbException`.
- Current `ReaderError` is a struct `{code, message}` — Dart caller must string-match `code` (no exhaustiveness).
- **Recommended: project-wide `AppError` enum** in `rust/src/api/error.rs`:

```rust
#[derive(Debug)]
pub enum AppError {
    NotFound { resource: String, id: String },
    InvalidInput(String),
    Network { url: String, status: u16, message: String },
    FeedParse { url: String, message: String },
    Database(String),
    Io(String),
    Unauthorized,
    Conflict(String),
}
```
Use `Result<T, AppError>` everywhere; Dart gets a typed enum it can `switch` over. Keep `anyhow` internal to the service layer; convert to `AppError` at the api boundary.

## 4. Codegen workflow

- Command: `flutter_rust_bridge_codegen gen` (reads the yaml at repo root).
- Regenerates `rust/src/frb_generated.rs` + `lib/src/rust/frb_generated*.dart` + `lib/src/rust/api/<module>.dart` per Rust module.
- Run after **every** change under `rust/src/api/**`. Generated files are committed; codegen is deterministic.
- `forceSameCodegenVersion: true` in `RustLib.init()` enforces runtime==codegen version — stale codegen fails loudly at startup.
- Keep `auto_upgrade_dependency: false` and the `254b193` pin. Add a `make frb` / `scripts/frb.sh` target to DoD.

## 5. Module structure

FRB recurses `crate::api` over `pub mod`s. Recommended layout mirroring Livo's `handlers/` (thin IPC) vs `services/` + `database/` split:

```
rust/src/
  api/                 # thin FRB-exposed wrappers (= Livo handlers/)
    mod.rs
    error.rs           # AppError enum (replaces ReaderError struct)
    types.rs           # shared DTOs/enums: Feed, Entry, ArticleViewMode, SyncProgress, ...
    app.rs             # init_app(), app version (replaces simple.rs role)
    feed.rs            # feed CRUD + subscribe + sync
    entry.rs           # entry list/get/mark-read/star/search
    settings.rs        # settings get/set
    discovery.rs       # P3, later
  db/                  # rusqlite pool, schema, migrations, repositories (NOT codegen-exposed)
  feed/                # fetch (reqwest) + parse (feed-rs) + normalization
  services/            # business logic the api layer calls into
  frb_generated.rs
  lib.rs
```
Rules: `api/*.rs` only (de)serialize DTOs and delegate to `services/`/`db/`; keep blocking/IO out of `api/`. FRB snake_case→camelCase; enum variants get a trailing underscore for Dart keywords (`External`→`external_`).

## 6. Init / lifecycle

- `init_app()` (`#[frb(init)]`) currently only calls `setup_default_user_utils()`. **Open the SQLite DB + run migrations here.**
- Store a connection pool in a `once_cell::sync::Lazy` static (e.g. `r2d2_sqlite`, or `Mutex<Connection>`/`Mutex<Vec<Connection>>`) so api fns can borrow without passing handles across the bridge. `rusqlite::Connection` is `!Send`/`!Sync` by default → pool + `spawn_blocking` is the safe pattern.
- Dart: `await RustLib.init();` once in `main()` before `runApp(...)`.

## Recommended bridge architecture (summary)

1. **Sync policy** — async by default; `#[frb(sync)]` only for tiny pure/indexed lookups. Wrap blocking rusqlite in `async fn` + `spawn_blocking`.
2. **Streaming** — `StreamSink<SyncProgress>` for feed sync (and later AI token streams); payload mirrors Livo `FeedRefreshProgressPayload`.
3. **Errors** — `AppError` enum in `rust/src/api/error.rs`; `Result<T, AppError>` everywhere; `anyhow` internal.
4. **Modules** — `api/{error,types,app,feed,entry,settings,discovery}.rs` thin wrappers over `db/`+`services/`+`feed/`.
5. **Codegen** — `flutter_rust_bridge_codegen gen` after each api change; commit generated; keep pin + `auto_upgrade_dependency: false`; add `make frb` target.
6. **Init** — `init_app()` opens DB pool + runs migrations; `RustLib.init()` in Dart `main()`.

## Caveats

- Live FRB docs (cjycode.com) are JS-rendered; all claims verified against in-repo generated v2.12.0 code (`frb_generated.rs/.dart`, `api/*.dart`). No stream fn exists in-repo yet — verify `StreamSink<T>` end-to-end with a trivial smoke fn when refactor starts.
- DB binding is the separate PRD open-question; the async + `spawn_blocking` recommendation assumes a **synchronous** binding (rusqlite). If **sqlx** (async) is chosen, `spawn_blocking` is unnecessary but compile-time SQL + async-driver maturity tradeoffs apply.
- Current Dart `reader_repository.dart` does HTTP in Dart; recommended architecture moves fetching into Rust (`reqwest`), changing the `importFeed` contract (no more `xmlContent` param from Dart) — flag for the P1 child task.
