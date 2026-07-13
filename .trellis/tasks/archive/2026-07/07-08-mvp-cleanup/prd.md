# MVP cleanup: redundant runtime, unused deps, clippy, gitignore, stray files

**Parent**: `07-07-livo-frb-refactor` · **Depends on**: P2b (MVP complete)

## Goal

Wrap up the MVP phase by clearing the small tech debt accumulated across
P0a-P2b. No new features - just simplification, dead-code/dep removal, lint, a
repo-config fix, and stray-file cleanup.

## Scope (in)

1. **Remove `rust/src/feed/runtime.rs`** - the redundant second tokio runtime.
   FRB v2.12 already runs `async fn` bodies on a multi-threaded tokio runtime
   with a reactor (see `directory-structure.md` gotcha). Change `api/feed.rs`
   (`discover_feeds`/`subscribe_feed`/`sync_feeds`/`refresh_all_feeds`/
   `refresh_feed`) to await `*_impl` directly instead of
   `runtime::handle().spawn(...).await`. Delete `feed/runtime.rs` + its module
   decl in `feed/mod.rs`. Verify async fetch/sync still works (BBC smoke).
2. **Remove the unused `http` pubspec dep** - P1a moved fetching to Rust;
   `reader_repository.dart` no longer imports `package:http`. Drop `http:` from
   `pubspec.yaml` + update `pubspec.lock` (`flutter pub get`).
3. **Fix pre-existing clippy warnings in `rust/src/feed/parse.rs`** -
   `unnecessary_lazy_evaluations`, `unnecessary_to_owned` (flagged by the P2b
   check). Behavior-identical fixes.
4. **`.gitignore` spec-tracking fix** - change the blanket `.trellis` line to
   `.trellis/*` + `!.trellis/spec/` so `.trellis/spec/` is consistently tracked
   (git can't re-include under a fully-ignored parent dir, so the `/*` form is
   required). Local state (`.runtime/`, `tasks/`, `workspace/`, `.developer`,
   `.backup-*`, `worktrees/`, `.cache/`, `.template-hashes.json`) stays ignored.
   After the change, `git status` should show `.trellis/spec/**` as trackable
   and NO local-state files. (Do NOT `git add -f .trellis/` wholesale.)
5. **Delete stray root `package.json` (`{}`) + `package-lock.json`** - web
   platform was dropped in an earlier commit; these are empty leftovers. Confirm
   both are empty/trivial before deleting.

## Acceptance Criteria

- [ ] `feed/runtime.rs` gone; async feed/sync fns await `*_impl` directly; `cargo test` + BBC smoke green
- [ ] `http` removed from `pubspec.yaml`/`.lock`; `flutter analyze` + `flutter test` green
- [ ] clippy clean on `feed/parse.rs` (no new warnings elsewhere)
- [ ] `.gitignore` tracks `.trellis/spec/`; local state still ignored; `git status` sensible
- [ ] stray `package.json`/`package-lock.json` deleted
- [ ] `cargo test` + `flutter analyze` + `flutter test` + `bash scripts/frb.sh` all green

## Out of Scope

- New features (P3-P6 roadmap). Functional gaps (`starredCount` accuracy,
  "Clear read" menu) - those are feature work, not tech debt.
- Removing the `path_provider`/`freezed`/etc. deps (all still used).
- Tracking `.trellis/scripts/` or `.trellis/workflow.md` (only `spec/` is un-ignored).

## Technical Notes

- `directory-structure.md` "FRB async fns already run on a tokio runtime" gotcha
- `research/frb-bridge-design.md` §1 (sync/async) + §6 (init/lifecycle)
- The `feed/runtime.rs` removal was explicitly deferred from P1a; this is the cleanup.
