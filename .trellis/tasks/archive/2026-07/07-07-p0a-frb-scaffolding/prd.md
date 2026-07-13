# P0a: FRB bridge scaffolding, core types & error model

**Parent**: `07-07-livo-frb-refactor` · **Depends on**: none (first task)

## Goal

Replace the throwaway JSON-snapshot bridge patterns with the project-wide FRB
architecture skeleton decided in the parent PRD: a typed `AppError` enum,
shared DTO types, the `api/*` module layout, a codegen target, and the Android
emulator `build.rs` fix. **No DB yet** — this lands the skeleton + toolchain so
P0b can build persistence on top.

## Scope (in)

- `rust/src/api/error.rs` — `AppError` enum (NotFound, InvalidInput, Network,
  FeedParse, Database, Io, Unauthorized, Conflict) bridging to a typed Dart
  enum (FrbException). Replaces the `ReaderError` struct.
- `rust/src/api/types.rs` — shared DTOs/enums: `Feed`, `Entry`, `Category`,
  `ArticleViewMode`, `SyncProgress`, `FeedDraft`, `EntryDraft`, etc. (port field
  shapes from Livo `src/shared/types/{feed,entry}.ts` + current `reader.rs`).
- `rust/src/api/app.rs` — `init_app()` (`#[frb(init)]`) placeholder (DB opens in
  P0b); re-export from `mod.rs`.
- `rust/src/api/mod.rs` — declare new modules; retire `simple.rs` (`greet`) into
  `app.rs`.
- `scripts/frb.sh` (or Makefile `frb` target) running
  `flutter_rust_bridge_codegen gen`; document in DoD.
- `rust/build.rs` — Android x86_64 `clang_rt.builtins` link fix (FRB #1719).
- Keep `flutter_rust_bridge.yaml` pin (`254b193`, `auto_upgrade_dependency: false`).
- Update `.trellis/spec/backend/*` stubs for Rust/FRB conventions
  (`database-guidelines.md` fully rewritten in P0b; here just add an FRB/bridge
  convention note + error-handling note).

## Acceptance Criteria

- [ ] `AppError` codegens to a typed Dart enum (exhaustive `switch` possible)
- [ ] `types.rs` DTOs codegen to Dart cleanly; `flutter analyze` + `cargo test` green
- [ ] `./scripts/frb.sh` regenerates bindings deterministically
- [ ] Android `build.rs` fix present + documented (emulator verification optional)
- [ ] `.trellis/spec/backend/` updated for the new conventions

## Out of Scope

- SQLite / persistence (P0b) · feed fetch/parse (P1a) · Flutter UI rewire
  (P1a/P2a) · retiring `reader.rs` snapshot fns fully (P0b removes them; P0a
  may leave them compiling but marked deprecated)

## Technical Notes

- Research: `research/frb-bridge-design.md` (sections 3, 4, 5)
- Livo types: `doc/Livo/src/shared/types/{feed,entry,index}.ts`
- Current throwaway: `rust/src/api/reader.rs` (struct `ReaderError`, `#[frb(sync)]` everywhere)
- FRB v2.12.0 pinned; enum variants needing Dart-keyword escaping get trailing `_`
