# Error Handling

> Rust-side error contracts for flutter_rust_bridge APIs.

## Project-wide error model: `AppError`

### 1. Scope / Trigger

- All FRB-facing Rust functions that can fail return `Result<T, AppError>`.
- `AppError` lives in `rust/src/api/error.rs` and is re-exported from `rust/src/api/mod.rs`.
- It replaces the legacy `ReaderError { code, message }` struct that lived in the former `reader.rs` snapshot prototype (removed in P2a).

### 2. The `AppError` enum

```rust
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

FRB generates this as a `@freezed sealed class` implementing `FrbException`, so Dart callers can `switch` over variants exhaustively (unlike the old `code` string).

> **Gotcha — `freezed` deps required.** Because `AppError` is a field-carrying
> enum, FRB generates it as `@freezed`. This requires `freezed_annotation` +
> `freezed` + `build_runner` in `pubspec.yaml` (already present after P0a) —
> see `directory-structure.md` → "FRB codegen gotchas". Any new field-carrying
> enum has the same requirement.

### 3. Conventions

- **`anyhow` is internal only.** The service / DB layer may use `anyhow::Result` internally, but every error must be converted to `AppError` before crossing the FRB boundary.
- **No `unwrap()` on user-controlled data.** URLs, JSON, IDs, etc. must be validated and converted to `AppError::InvalidInput` or the appropriate variant.
- **Helper constructors** (`not_found`, `invalid_input`, `database`) are `pub(crate)` — they are Rust-side convenience only and must not be exposed to Dart.
- `AppError` implements `std::fmt::Display` and `std::error::Error` for Rust-side logging.

### 4. Validation & Error Matrix

| Condition | Variant |
|-----------|---------|
| Empty or malformed URL | `InvalidInput` |
| Duplicate feed subscription | `Conflict` or `InvalidInput` |
| Missing article / feed / category during mutation | `NotFound` |
| Unsupported XML shape or invalid snapshot JSON | `FeedParse` |
| HTTP failure (non-2xx, timeout, DNS) | `Network` |
| SQLite / migration failure | `Database` |
| Filesystem error | `Io` |
| Auth required / token expired | `Unauthorized` |

### 5. Wrong vs Correct

#### Wrong

- `unwrap()` on parsed snapshot, feed URLs, or DB query results
- Returning ad hoc strings or opaque internal errors
- Letting `anyhow::Error` cross the FRB boundary

#### Correct

- Convert all boundary failures into `AppError`
- Use `?` with `From` impls (added in P0b for io/serde/DB errors) to propagate naturally
- Keep validation failures explicit so Flutter can surface them in snackbars / dialogs

---

## Legacy: `ReaderError` (removed in P2a)

The throwaway JSON-snapshot functions in the former `rust/src/api/reader.rs`
used `ReaderError { code, message }` with error codes (`invalid_input`,
`not_found`, `parse_error`). These were superseded by `AppError`. P0b landed the
SQLite persistence layer but intentionally kept `reader.rs` compiling (the
Flutter UI still called the snapshot APIs); P1a/P1b kept it for the same reason.
P2a rewired the reading UI onto the persisted entry APIs and removed `reader.rs`
along with `ReaderError` (and the stale generated `lib/src/rust/api/reader.dart`).
`AppError` is now the sole error type at the FRB boundary.
