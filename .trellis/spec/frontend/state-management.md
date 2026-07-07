# State Management

> Flutter-side state conventions for this project.

## Scenario: Rust-backed reader snapshot

### 1. Scope / Trigger

- Trigger: Cross-layer reader state now spans Flutter UI, local persistence, HTTP fetching, FRB bindings, and Rust domain logic.
- This requires a concrete contract because Flutter and Rust do not share in-memory state directly.

### 2. Signatures

- `Future<ReaderController> bootstrapReaderController({ReaderRepository? repository})`
- `Future<String> ReaderRepository.loadSnapshotJson()`
- `Future<void> ReaderRepository.saveSnapshotJson(String snapshotJson)`
- `Future<ImportFeedResult> ReaderRepository.importFeed({required String snapshotJson, required String feedUrl})`
- `emptyReaderSnapshotJson() -> String`
- `decodeReaderSnapshot({required String snapshotJson}) -> ReaderSnapshot`
- `listArticles({required String snapshotJson, String? feedId, required bool showStarredOnly, required bool showUnreadOnly}) -> List<ArticleListItem>`
- `importFeedFromXml({required String snapshotJson, required String feedUrl, required String xmlContent}) -> Future<ImportFeedResult>`

### 3. Contracts

- Flutter owns:
  - `http` feed fetching
  - `shared_preferences` persistence
  - view-only selection state such as `selectedFeedId`, `selectedArticleId`, `showStarredOnly`, and `showUnreadOnly`
- Rust owns:
  - snapshot decoding and serialization
  - feed merge logic
  - read/star mutations
  - RSS / Atom parsing
- Persisted reader state is a single JSON blob stored under `reader_snapshot_v1`.
- Every Rust mutation takes the current `snapshotJson` and returns a full replacement snapshot.
- The controller must persist the returned snapshot before treating it as durable state.

### 4. Validation & Error Matrix

- Empty storage -> initialize from `emptyReaderSnapshotJson()`
- Feed HTTP status outside `200..299` -> throw `ReaderAppException`
- Empty feed response body -> throw `ReaderAppException`
- Invalid snapshot JSON -> Rust returns `ReaderError(code: "parse_error", ...)`
- Invalid feed URL -> Rust returns `ReaderError(code: "invalid_input", ...)`
- Selected article disappears after filtering or cleanup -> controller clears selection or falls back to the first visible article
- Single feed refresh failure -> controller records the error via `recordFeedError`, persists the snapshot, and continues refreshing remaining feeds

### 5. Good / Base / Bad Cases

- Good: Fetch XML in Flutter, call Rust import, persist returned snapshot, then derive UI lists from the new snapshot
- Base: No stored snapshot yet -> app starts with an empty reader state and add-feed CTA
- Bad: Mutate derived Dart lists without updating the Rust snapshot; that creates UI state drift and breaks persistence

### 6. Tests Required

- Rust unit tests for parser behavior and snapshot mutation invariants
- Flutter widget or integration test with a fake HTTP client that verifies feed import end to end
- When changing the snapshot schema or mutation semantics, test both:
  - Rust-side result contents
  - Flutter-side controller selection and persistence flow

### 7. Wrong vs Correct

#### Wrong

- Store feeds and articles in separate Flutter caches and try to mirror Rust mutations manually
- Fetch XML in Rust and persist files in Rust for every platform in the MVP

#### Correct

- Keep one persisted snapshot string in Flutter
- Let Rust remain the single writer for reader domain state
- Treat Flutter controller fields as ephemeral view state rebuilt from the latest snapshot

### 8. Common Mistake: Adding a persisted Rust field across FRB

**Symptom**: After adding a field to a Rust struct (e.g. `Feed.error_count: i32`) that is part of the snapshot JSON and crosses FRB to Dart, either (a) existing users' snapshots fail to load, or (b) the Dart test mock crashes in `Feed.fromJson` on a missing field.

**Cause**: The Rust struct is the source of truth, but the field appears in three places that must stay in sync: Rust serde, the FRB-generated Dart class, and any hand-built JSON in the Dart test mock. Old snapshots on disk lack the new field, and the generated Dart `fromJson` treats non-nullable Rust types (`i32`, `String`) as required.

**Fix**:
- Mark the new Rust field `#[serde(default)]` (and `Option<T>` for nullable). Old snapshots then decode in Rust with the default.
- Because Rust owns `decode_snapshot` and re-serializes before FRB returns to Dart, the generated Dart `fromJson` always receives the field — Dart never sees a missing field at runtime. (Verified by `legacy_snapshot_without_error_fields_decodes`.)
- The Dart test mock is the exception: it builds JSON maps by hand and bypasses Rust, so every mock Feed map MUST include non-nullable fields (`'errorCount': 0`, `'lastError': null`) or `Feed.fromJson` throws in tests.

**Prevention**: When adding any field to `Feed` / `Article` / `ArticleListItem`, update in one pass: Rust struct (+ `#[serde(default)]`) → all Rust `Feed { ... }` construction sites → run `flutter_rust_bridge_codegen generate` → every Feed/Article JSON map in `test/reader_import_test.dart`'s `_MockRustApi`. Add a Rust test that decodes a legacy snapshot missing the field.

