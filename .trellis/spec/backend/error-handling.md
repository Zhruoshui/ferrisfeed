# Error Handling

> Rust-side error contracts for flutter_rust_bridge APIs.

## Scenario: Reader FRB error contract

### 1. Scope / Trigger

- Trigger: Reader APIs are now consumed by Flutter through FRB and must return stable, displayable errors across the language boundary.

### 2. Signatures

- `decode_reader_snapshot(snapshot_json: String) -> Result<ReaderSnapshot, ReaderError>`
- `add_feed(...) -> Result<String, ReaderError>`
- `remove_feed(...) -> Result<String, ReaderError>`
- `mark_article_read(...) -> Result<String, ReaderError>`
- `toggle_article_star(...) -> Result<String, ReaderError>`
- `clear_all_read_articles(...) -> Result<String, ReaderError>`
- `import_feed_from_xml(...) -> Result<ImportFeedResult, ReaderError>`

### 3. Contracts

- FRB-facing errors use:
  - `code: String`
  - `message: String`
- Current error codes:
  - `invalid_input`
  - `not_found`
  - `parse_error`
- The `message` must be user-readable enough for Flutter snackbars and dialogs.
- The `code` must stay machine-stable for branching and regression tests.

### 4. Validation & Error Matrix

- Empty or malformed URL -> `invalid_input`
- Duplicate feed subscription -> `invalid_input`
- Missing article or feed during mutation -> `not_found`
- Unsupported XML shape or invalid snapshot JSON -> `parse_error`

### 5. Good / Base / Bad Cases

- Good: Reject malformed input at the Rust boundary and return a structured `ReaderError`
- Base: Empty snapshot string decodes to an empty reader state instead of failing
- Bad: Panic, unwrap user-controlled data, or return opaque internal errors that Flutter cannot classify

### 6. Tests Required

- Unit test parser acceptance for representative RSS / Atom payloads
- Unit test deduplication and count recalculation after mutation
- When adding a new error condition, assert both the `code` and the high-level behavior in tests

### 7. Wrong vs Correct

#### Wrong

- `unwrap()` on parsed snapshot or feed URLs from user input
- Returning ad hoc strings without a stable `code`

#### Correct

- Convert boundary failures into `ReaderError`
- Keep parse and validation failures explicit so Flutter can surface them directly
