# Implementation Plan: P4 AI article summary and translation

## Ordered checklist

### 1. Database schema and repository layer

- [ ] Add migration `V4_AI_COLUMNS` in `rust/src/db/migrations.rs`:
  - `ALTER TABLE entries ADD COLUMN ai_summary TEXT;`
  - `ALTER TABLE entries ADD COLUMN ai_translation_zh TEXT;`
  - Append to `Migrations::new(...)` and bump schema version.
- [ ] Add `ai_summary` and `ai_translation_zh` fields to the `Entry` struct in `rust/src/api/types.rs`.
- [ ] Update `entry_from_row` in `rust/src/db/repositories/entry.rs` to read the new columns.
- [ ] Add repository helpers in `rust/src/db/repositories/entry.rs`:
  - `get_entry_ai_text(conn, id)`
  - `set_entry_ai_summary(conn, id, value)`
  - `set_entry_ai_translation_zh(conn, id, value)`

### 2. Backend AI module

- [ ] Create `rust/src/ai/mod.rs`.
- [ ] Create `rust/src/ai/config.rs`:
  - `AiConfig` DTO (also re-export/expose in `api/types.rs`).
  - Load/save from `settings` table with defaults.
- [ ] Create `rust/src/ai/client.rs`:
  - Shared `reqwest::Client`.
  - `chat_completion(config, messages) -> Result<String, AppError>`.
  - Request/response structs.
- [ ] Create `rust/src/ai/prompts.rs`:
  - `summary_prompt(title, body, lang)`.
  - `translation_prompt(title, body, target)`.
  - Plain-text stripping helper.
- [ ] Create `rust/src/ai/service.rs`:
  - `summarize_entry(entry_id) -> Result<String, AppError>`.
  - `translate_entry(entry_id, target_language) -> Result<String, AppError>`.
  - Check DB cache before calling LLM.

### 3. FRB API

- [ ] Create `rust/src/api/ai.rs`:
  - `summarize_entry(entry_id: String) -> Result<String, AppError>`
  - `translate_entry(entry_id: String, target_language: String) -> Result<String, AppError>`
  - `get_ai_config() -> Result<AiConfig, AppError>`
  - `set_ai_config(config: AiConfig) -> Result<(), AppError>`
- [ ] Add `pub mod ai;` to `rust/src/api/mod.rs`.
- [ ] Regenerate FRB bindings by running `./scripts/frb.sh`.

### 4. Flutter controller and state

- [ ] Add `AiConfig` and `AiViewMode` imports in `lib/src/app/reader_controller.dart`.
- [ ] Add fields:
  - `AiConfig? _aiConfig`
  - `AiViewMode _aiViewMode = AiViewMode.original`
  - `Map<String, String> _aiResults` (key = `entryId:summary|translation`)
- [ ] Load `_aiConfig` in `_loadPersistedSettings`.
- [ ] Add methods:
  - `Future<AiConfig> getAiConfig()`
  - `Future<void> setAiConfig(AiConfig config)`
  - `Future<String> summarizeSelectedArticle()`
  - `Future<String> translateSelectedArticle()`
  - `String? aiResultFor(String entryId, AiViewMode mode)`
- [ ] Reset `_aiViewMode` to `original` when `openArticle` is called.

### 5. Flutter UI

- [ ] Create `lib/src/app/ai_panel.dart`:
  - Segmented Original/Summary/Translation controls.
  - Loading and error states.
  - HTML-aware rendering.
- [ ] Create `lib/src/app/ai_settings_dialog.dart` modeled on `_RsshubSettingsDialog`.
- [ ] Update `lib/src/app/article_detail_view.dart`:
  - Insert `AiPanel` above the font controls in `_RenderedArticleView`.
- [ ] Update `lib/src/app/reader_app.dart`:
  - Add `aiSettings` to `_ReaderMenuAction` and menu builder.
  - Add Summarize/Translate icon buttons to `_ArticleDetailHeader`.
  - Handle `_ReaderMenuAction.aiSettings`.

### 6. Validation and cleanup

- [ ] Run `cargo fmt` in `rust/`.
- [ ] Run `cargo clippy --all-targets` and fix warnings.
- [ ] Run `cargo test`.
- [ ] Run `flutter analyze`.
- [ ] Run `./scripts/frb.sh` and ensure generated files are committed.
- [ ] Manual smoke test: open an article, configure a test endpoint, summarize, translate, switch modes, restart app and verify cache.

## Risky files / rollback points

- `rust/src/db/migrations.rs` — must keep migrations idempotent; if a mistake is made here, revert before committing.
- `rust/src/api/types.rs` — adding fields to `Entry` triggers FRB regeneration; if codegen fails, roll back to the previous struct shape.
- `lib/src/rust/api/*.dart` and `lib/src/rust/frb_generated*.dart` — auto-generated; do not hand-edit. Regenerate via `./scripts/frb.sh`.
- `rust/Cargo.toml` — no new crates are required for MVP (uses existing `reqwest`/`serde_json`); avoid adding dependencies unless absolutely necessary.

## Validation commands

```bash
cd rust
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test

cd ..
./scripts/frb.sh
flutter analyze
```

## Follow-up checks before `task.py start`

- [ ] `prd.md` passes convergence pass (no duplicate facts, testable acceptance criteria).
- [ ] `design.md` and `implement.md` are complete.
- [ ] `implement.jsonl` and `check.jsonl` contain real entries (not just the seed `_example`).
