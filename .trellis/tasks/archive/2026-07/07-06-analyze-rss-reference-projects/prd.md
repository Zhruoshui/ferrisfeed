# Analyze RSS reference projects

## Goal

Analyze the two local reference RSS reader projects under `doc/MrRSS` and `doc/oksskolten`, then write separate feature and architecture analysis reports for FerrisFeed planning.

## Requirements

- Inspect `doc/MrRSS` and summarize product positioning, architecture, RSS subscription support, article rendering, storage, AI features, automation, and lessons applicable to FerrisFeed.
- Inspect `doc/oksskolten` and summarize product positioning, architecture, RSS subscription support, article rendering, storage, AI features, refresh strategy, PWA/server concerns, and lessons applicable to FerrisFeed.
- Write the MrRSS report under `doc/ref/MrRSS/`.
- Write the oksskolten report under `doc/ref/obsskolren/` as requested by the user.
- Keep reports grounded in local source files, READMEs, docs, migrations, and tests.

## Acceptance Criteria

- [x] `doc/ref/MrRSS/` contains a Markdown analysis report.
- [x] `doc/ref/obsskolren/` contains a Markdown analysis report.
- [x] Each report includes concrete feature opportunities and cautions for FerrisFeed.
- [x] The analysis avoids implementation changes to FerrisFeed runtime code.

## Definition of Done

- Reports are written in Chinese.
- Paths requested by the user are created if missing.
- Relevant local reference files are inspected before writing conclusions.
- Working tree changes are limited to task metadata and report files unless a tool creates expected Trellis artifacts.

## Out of Scope

- Implementing any FerrisFeed feature.
- Running or modifying the two reference projects.
- Web research beyond the local reference code.

## Technical Notes

- FerrisFeed is currently Flutter + Rust with `snapshot_json` persisted by Flutter and RSS/Atom parsing/domain state handled by Rust.
- Current FerrisFeed core files reviewed previously: `lib/src/app/reader_app.dart`, `lib/src/app/reader_controller.dart`, `lib/src/app/reader_repository.dart`, `lib/src/app/article_detail_view.dart`, `rust/src/api/reader.rs`.
- Local references:
  - `doc/MrRSS`
  - `doc/oksskolten`
