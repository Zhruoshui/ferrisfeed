# Article Detail Webpage and Rendered Views

## Goal

Implement article detail viewing so subscribed RSS/Atom entries actually display useful content in FerrisFeed. Users should be able to view an article either as the original webpage or as rendered feed content, with behavior that works generally across feeds rather than only for one source.

## What I Already Know

* FerrisFeed is a Flutter + Rust + `flutter_rust_bridge` RSS/Atom reader.
* Flutter owns UI, platform behavior, and local interactions.
* Rust owns feed domain models, state transitions, and RSS/Atom XML parsing.
* `doc/MrRSS` is available as a functional reference implementation.
* The user wants two article view options:
  * View article as webpage.
  * View article as rendered content.
* Test feeds called out by the user:
  * `https://daily.juya.uk/rss.xml`
  * `https://news.ycombinator.com/rss`

## Requirements

* Article selection must render readable detail content on the right-hand side.
* Provide article viewing modes equivalent to:
  * `global`: follow the app default mode.
  * `webpage`: show the article URL as an in-app webpage where supported.
  * `rendered`: render RSS/Atom-provided article content in the app.
  * `external`: open the article in the system browser.
* Feed-level mode should be stored with each feed and default to `global`.
* The rendered view must handle common feed HTML content, including paragraphs, links, images, headings, lists, blockquotes, code/preformatted text, and tables where Flutter support allows.
* The webpage view must be generic and should not require per-feed hardcoding.
* The feature should work for both content-rich feeds like `daily.juya.uk/rss.xml` and link-style feeds like `news.ycombinator.com/rss`.
* Existing subscription and article list behavior should remain intact.

## Acceptance Criteria

* [ ] After subscribing to `https://daily.juya.uk/rss.xml`, opening an article displays readable article content in rendered mode.
* [ ] After subscribing to `https://news.ycombinator.com/rss`, opening an article displays a useful article detail view and preserves outbound links.
* [ ] Feed-level article view mode can be set and persisted.
* [ ] `webpage` mode opens the original article URL in the in-app detail area on platforms where the app supports embedded web content.
* [ ] `external` mode opens the system browser instead of the in-app detail view.
* [ ] `global` mode follows the current app default.
* [ ] Rust parsing/persistence exposes enough article content data for Flutter to render the detail view.
* [ ] Project lint/type checks pass for touched layers.

## Definition of Done

* Tests added or updated where practical for model parsing, persistence, and view-mode behavior.
* Flutter analysis passes.
* Rust checks/tests pass for touched crates.
* Cross-layer data flow is verified from feed parse to persisted article to Flutter detail rendering.
* No source-specific hardcoding for the two test feeds.

## Technical Approach

Inspect the existing Flutter/Rust data model first. Prefer extending current feed and article models, database schema, and detail UI rather than introducing a parallel pipeline. Use `doc/MrRSS` only as a reference for behavior and field semantics, not as a literal implementation target.

## Decision (ADR-lite)

**Context**: Article display spans feed configuration, article model/persistence, XML parsing, Flutter rendering, and platform-specific navigation.

**Decision**: Implement feed-level article view mode and choose the effective mode at article-open time. Render stored feed content inside Flutter for `rendered`; open the article URL through embedded web content for `webpage` where supported; delegate to the platform browser for `external`.

**Consequences**: This keeps feed parsing and content storage reusable across platforms while leaving room for later improvements such as readability extraction, media proxying, or per-article overrides.

## Out of Scope

* Full readability extraction from arbitrary webpages.
* Backend HTTP proxy equivalent to MrRSS unless the current architecture already has or clearly needs one.
* Translation, summarization, media download, or math rendering.
* Feed-specific rendering branches for the two test URLs.

## Technical Notes

* Relevant specs to read before implementation:
  * `.trellis/spec/backend/index.md`
  * `.trellis/spec/frontend/index.md`
  * `.trellis/spec/guides/cross-layer-thinking-guide.md`
  * `.trellis/spec/guides/code-reuse-thinking-guide.md`
* Reference implementation notes are under `doc/MrRSS`.
