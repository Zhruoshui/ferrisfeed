# P4 AI article summary and translation

## Goal

Add AI-powered article summary and translation to the RSS reader. Users can generate a concise summary of any article and translate article content into Simplified Chinese on demand, using an externally configurable OpenAI-compatible LLM provider.

## Background

- The app is Flutter frontend + Rust backend via `flutter_rust_bridge` v2.12.
- Article DTO: Rust `Entry` in `rust/src/api/types.rs:140-154`, exposed to Dart as `Entry` in `lib/src/rust/api/types.dart:67-132`. The existing `summary` field holds the feed-provided summary, not AI output.
- Article detail UI: `lib/src/app/article_detail_view.dart` renders content via `HtmlWidget` at line 109. The toolbar is `_ArticleDetailHeader` in `lib/src/app/reader_app.dart:1376-1486`.
- Settings: Rust SQLite `settings` key/value table (migration v3, `rust/src/db/migrations.rs:98-102`) is the intended place for P4 config knobs (`rust/src/api/settings.rs`).
- No AI/LLM integration or localization setup exists yet.

## Decisions

- **LLM API protocol:** OpenAI-compatible `/chat/completions`. Configuration: endpoint URL, model name, API key.
- **Translation target:** 简体中文 (Simplified Chinese) only for this iteration.
- **Display mode:** AI result shown in a separate panel/card at the top of the article detail view, with controls to switch among **Original**, **Summary**, and **Translation**. The original article is always preserved.
- **Summary language:** AI summaries are generated in the configured target language (简体中文).
- **Caching:** Both summary and translation are cached per article in the local database.

## Requirements

- R1. Provide AI provider configuration in app settings: endpoint URL, model name, API key, and default translation target language.
- R2. From the article detail screen, allow the user to generate an AI summary for the current article.
- R3. From the article detail screen, allow the user to translate the article content into Simplified Chinese.
- R4. Display generated summary/translation inline in the article detail view inside a dedicated panel.
- R5. Cache generated AI results per article so they survive app restarts and avoid repeated API calls.
- R6. If no provider is configured or the request fails, surface a clear, non-blocking error message in the UI.

## Acceptance Criteria

- [ ] User can open AI settings and configure endpoint URL, model name, API key, and target language.
- [ ] Tapping "Summarize" on an article produces a concise summary in 简体中文 and shows it in the AI panel.
- [ ] Tapping "Translate" on an article produces a Simplified Chinese translation and shows it in the AI panel.
- [ ] The user can switch between Original, Summary, and Translation views without re-fetching from the LLM when cached.
- [ ] Generated summaries/translations are persisted in the local database and reappear after app restart.
- [ ] When no provider is configured, the UI shows a configuration hint instead of crashing or silently failing.
- [ ] `cargo clippy`, `cargo test`, `flutter analyze`, and the FRB codegen script all pass.

## Out of scope

- Multiple translation target languages or language auto-detection.
- Bilingual side-by-side display.
- Chat / RAG functionality.
- Automatic summarization on article open.
- Provider-specific UIs beyond a single OpenAI-compatible endpoint.
