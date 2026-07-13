# Design: P4 AI article summary and translation

## Architecture and boundaries

```
Flutter UI  <--FRB-->  rust/src/api/ai.rs  -->  rust/src/ai/  (client + prompts + config)
                            |                          |
                            v                          v
                   rust/src/db/repositories/entry  reqwest HTTP client
```

- `rust/src/ai/` is a new non-exposed module (mirrors `feed/`). It owns the LLM HTTP client, prompt templates, and configuration parsing.
- `rust/src/api/ai.rs` is the thin FRB-exposed layer: async functions that delegate to `rust/src/ai/`.
- `rust/src/db/repositories/entry.rs` gets new functions to read/write `ai_summary` and `ai_translation_zh` columns.
- Flutter side adds a new AI panel widget and an AI settings dialog; `ReaderController` mediates state and calls the generated `rust_ai.*` functions.

## Data flow

### Summary

1. User taps "Summarize" in `_ArticleDetailHeader`.
2. `ReaderController` checks the in-memory cache for the selected entry; if missing, calls `rust_ai.summarizeEntry(entryId: entry.id)`.
3. Rust API:
   - Loads the entry from SQLite (`entries.title`, `content`, `summary`).
   - Loads AI provider config from `settings`.
   - Falls back to a clear `AppError::InvalidInput` if config is missing.
   - Calls the LLM with a summary prompt.
   - Writes the result to `entries.ai_summary`.
   - Returns the summary text.
4. Controller stores the result and switches the AI panel to **Summary**.
5. UI re-renders the panel with the summary rendered as HTML (plain paragraphs wrapped in `<p>`).

### Translation

1. User taps "Translate".
2. `ReaderController` calls `rust_ai.translateEntry(entryId: entry.id, targetLanguage: 'zh')`.
3. Rust API loads entry + config, calls the LLM with a translation prompt, writes the result to `entries.ai_translation_zh`, and returns it.
4. UI switches the panel to **Translation**.

### Cache hit

- When the panel switches to Summary/Translation, the controller first checks the in-memory cache. If present, it displays immediately.
- If not in memory but present in the DB, the controller will load it via the same API (the Rust function returns the cached value without calling the LLM).

## Database changes

Add a new migration `V4_AI_COLUMNS` in `rust/src/db/migrations.rs` after `V3_SETTINGS_AND_PROVIDER`:

```sql
ALTER TABLE entries ADD COLUMN ai_summary TEXT;
ALTER TABLE entries ADD COLUMN ai_translation_zh TEXT;
```

Update `entry_from_row` in `rust/src/db/repositories/entry.rs:338-357` to map the new columns into the `Entry` DTO. Because `Entry` is FRB-exposed, adding fields requires regenerating FRB bindings.

Add repository helpers:

- `get_entry_ai_text(conn, id) -> Result<(Option<String>, Option<String>), AppError>` (used by the AI service before calling the LLM).
- `set_entry_ai_summary(conn, id, value) -> Result<(), AppError>`
- `set_entry_ai_translation_zh(conn, id, value) -> Result<(), AppError>`

## Backend: AI module

### New files

- `rust/src/ai/mod.rs` — module exports.
- `rust/src/ai/config.rs` — `AiConfig` struct loaded from `settings` keys:
  - `ai.endpoint` → default `"https://api.openai.com/v1/chat/completions"`
  - `ai.model` → default `"gpt-4o-mini"`
  - `ai.api_key` → no default
  - `ai.target_language` → default `"zh"`
- `rust/src/ai/client.rs` — shared `reqwest::Client`, `chat_completion(request) -> Result<String, AppError>`, and request/response types.
- `rust/src/ai/prompts.rs` — prompt builders:
  - `summary_prompt(title: &str, body: &str, lang: &str) -> Vec<Message>`
  - `translation_prompt(title: &str, body: &str, target: &str) -> Vec<Message>`
- `rust/src/ai/service.rs` — `summarize_entry(entry_id, lang)`, `translate_entry(entry_id, target)`.

### Request/response shape

OpenAI-compatible chat completion request:

```json
{
  "model": "gpt-4o-mini",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "<prompt>"}
  ],
  "temperature": 0.3,
  "max_tokens": 2048
}
```

Response parsing extracts `choices[0].message.content`.

### Error mapping

- Missing endpoint/model/key → `AppError::InvalidInput`.
- HTTP non-2xx / transport failure → `AppError::Network`.
- Missing or malformed JSON response → `AppError::InvalidInput`.

## FRB API surface

New `rust/src/api/ai.rs` (add `pub mod ai;` to `rust/src/api/mod.rs`):

```rust
#[flutter_rust_bridge::frb]
pub async fn summarize_entry(entry_id: String) -> Result<String, AppError>;

#[flutter_rust_bridge::frb]
pub async fn translate_entry(
    entry_id: String,
    target_language: String,
) -> Result<String, AppError>;

#[flutter_rust_bridge::frb]
pub fn get_ai_config() -> Result<AiConfig, AppError>;

#[flutter_rust_bridge::frb]
pub fn set_ai_config(config: AiConfig) -> Result<(), AppError>;
```

`AiConfig` is a new DTO in `rust/src/api/types.rs`:

```rust
#[flutter_rust_bridge::frb(unignore)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AiConfig {
    pub endpoint: String,
    pub model: String,
    pub api_key: String,
    pub target_language: String,
}
```

Because it carries only primitive fields, FRB codegens it as a plain Dart class.

## Frontend changes

### New files

- `lib/src/app/ai_panel.dart` — `AiPanel` widget:
  - Accepts `Entry`, `AiViewMode` (original/summary/translation), loading state, error, and callbacks (`onSummarize`, `onTranslate`, `onSwitchMode`).
  - Renders Original/Summary/Translation segmented buttons.
  - Renders AI output as `HtmlWidget` or plain `Text` if not HTML.
  - Shows inline loading indicator and error message.
- `lib/src/app/ai_settings_dialog.dart` — `_AiSettingsDialog` modeled on `_RsshubSettingsDialog` (`reader_app.dart:2115-2284`):
  - Fields for endpoint, model, API key, target language dropdown (简体中文 / English).
  - Loads current config via `ReaderController.getAiConfig()` and saves via `setAiConfig()`.

### Modified files

- `lib/src/app/article_detail_view.dart`:
  - Add `AiPanel` above `_ReadingFontControls` in `_RenderedArticleView`.
  - Pass current `AiViewMode` and AI output from the controller.
- `lib/src/app/reader_app.dart`:
  - Add `aiSettings` to `_ReaderMenuAction` enum and menu.
  - Add "Summarize" and "Translate" `IconButton`s to `_ArticleDetailHeader` toolbar (around line 1445).
  - Handle `_ReaderMenuAction.aiSettings` in `_handleMenuAction`.
- `lib/src/app/reader_controller.dart`:
  - Add `AiConfig? _aiConfig` cache and load it in `_loadPersistedSettings`.
  - Add `AiViewMode _aiViewMode = AiViewMode.original`.
  - Add getters/setters for `aiViewMode`.
  - Add `Future<String> summarizeSelectedArticle()` and `Future<String> translateSelectedArticle()`.
  - Cache generated text in `_aiResults` map keyed by `entryId + mode`.
  - Add `Future<AiConfig> getAiConfig()` and `Future<void> setAiConfig(AiConfig config)`.

### State management

- The controller owns the current `AiViewMode` and the in-memory AI output cache.
- When the user switches modes, the controller returns cached text if available; otherwise it triggers the Rust API.
- If the user opens a different article, `_aiViewMode` resets to `original` and the cache key changes.

## Prompts

### Summary

System: `You are a concise article summarizer.`
User:
```
请用简体中文为下面的文章生成一段简短摘要（不超过 3 句话）。只输出摘要内容，不要解释。

标题：<title>

正文：<body>
```

### Translation

System: `You are a precise translator.`
User:
```
请将下面的文章翻译成简体中文。保留原文的段落结构，只输出译文，不要解释。

标题：<title>

正文：<body>
```

The `<body>` is derived from `entry.content` if present, otherwise `entry.summary`. HTML tags are stripped to plain text before sending to reduce token usage.

## Security and privacy

- The API key is stored as plaintext in the local SQLite database. This matches the existing local-first threat model; no server-side storage.
- Only `http`/`https` endpoints are accepted (validated in the settings dialog and the Rust client).
- The LLM request body does not include any user identifiers beyond the article content.

## Compatibility and rollback

- The migration adds nullable columns; existing rows will simply return `None` for AI fields.
- Removing the feature later is a simple schema revert (drop columns) and code removal.
- The new `AiConfig` DTO and API additions are additive; they do not break existing feed/entry APIs.

## Operational considerations

- LLM calls are explicit user actions, so there is no background sync cost surprise.
- Token limits: summary prompt caps output at a few sentences; translation prompt caps at `max_tokens: 2048`. Long articles may be truncated if they exceed the model's context window; for MVP we send the full body and rely on the provider to handle context limits.
- Network timeout follows the existing `reqwest` client default of 30 seconds.
