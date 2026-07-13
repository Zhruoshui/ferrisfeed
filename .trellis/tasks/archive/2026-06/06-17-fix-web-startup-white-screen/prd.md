# Fix web startup white screen

## Goal

Fix the Flutter web startup white screen while preserving the already verified Linux and Android behavior. The immediate cause has been reproduced and points to stale Flutter Rust Bridge web artifacts, not MCP logic itself.

## What I Already Know

* User reported web starts to a white screen.
* Linux and Android have already verified MCP functionality as OK.
* A previous FRB web issue is documented in `doc/ref/web-platform-fix.md`.
* `pubspec.yaml` and `rust/Cargo.toml` already point `flutter_rust_bridge` to git rev `254b193`, the revision from the previous web-platform fix.
* Current Dart and Rust generated bridge files agree on content hash `-1008744160`:
  * `lib/src/rust/frb_generated.dart`
  * `rust/src/frb_generated.rs`
* Browser-loaded web WASM currently reports Rust-side content hash `-1918914929`.
* `web/pkg/rust_lib_rss_reader_bg.wasm` is older than the current generated bridge files, and `flutter build web` copies that stale artifact into `build/web/pkg/`.

## Root Cause

The web white screen is caused by a Flutter Rust Bridge content hash mismatch during `RustLib.init()`.

In `lib/main.dart`, the app waits for `bootstrapReaderController()` before `runApp()`. That bootstrap calls `await RustLib.init()`. When FRB detects that Dart generated code and the loaded Rust/WASM artifact are out of sync, it throws before Flutter mounts the UI. The result is a pure white page.

Captured browser exception:

```text
Bad state: Content hash on Dart side (-1008744160) is different from Rust side (-1918914929), indicating out-of-sync code.
```

This is distinct from the earlier `DataCloneError` / `WorkerPool` issue in `doc/ref/web-platform-fix.md`. The previous dependency fix is present; the current failure is stale web build output.

## Requirements

* Regenerate or rebuild FRB web artifacts so the WASM side reports the same content hash as the generated Dart/Rust bridge code.
* Verify web startup with COOP/COEP headers enabled.
* Keep Linux and Android behavior unchanged.
* Preserve the existing FRB git dependency unless investigation proves a newer stable version is needed.
* Record the web rebuild command or guardrail so future Rust API/codegen changes do not leave `web/pkg` stale again.

## Acceptance Criteria

* [ ] `flutter run -d web-server --release --web-header=Cross-Origin-Opener-Policy=same-origin --web-header=Cross-Origin-Embedder-Policy=require-corp` serves the app without a content hash exception.
* [ ] Headless Chromium screenshot shows the RSS reader UI rather than a blank white page.
* [ ] Browser console has no uncaught FRB startup exception.
* [ ] `web/pkg/rust_lib_rss_reader_bg.wasm` matches the current generated bridge hash.
* [ ] Existing Flutter tests still pass.
* [ ] Linux/Android MCP assumptions are not regressed by the web fix.

## Definition of Done

* Tests added or updated if the fix changes source behavior.
* `flutter test` passes.
* Web startup manually verified through local web-server with COOP/COEP headers.
* Any required generated files or ignored artifact workflow are documented.
* No unrelated refactors.

## Technical Approach

1. Re-run the FRB web artifact generation path from `doc/ref/web-platform-fix.md`, at minimum `flutter_rust_bridge_codegen build-web`.
2. If generated Dart/Rust bindings change or the build still mismatches, also run `flutter_rust_bridge_codegen generate` before `build-web`.
3. Rebuild and serve web with COOP/COEP headers.
4. Use headless Chromium/CDP to verify there is no `RustLib.init()` exception and the UI renders.
5. Consider adding a lightweight developer script or documentation note for the required web rebuild step after Rust API/codegen changes.

## Research References

* [`research/web-white-screen-root-cause.md`](research/web-white-screen-root-cause.md) - reproduction evidence and root-cause analysis.

## Open Questions

* Should this task only refresh the stale web artifacts, or should it also add a small repeatable command/check to prevent future `web/pkg` hash drift?

## Out of Scope

* Changing MCP behavior or protocol logic.
* Redesigning the RSS reader UI.
* Reworking Linux/Android Rust build integration.
* Production hosting configuration beyond confirming required COOP/COEP headers.

## Technical Notes

* `web/pkg/` and `build/` are ignored by git, so stale local web artifacts can persist without appearing in `git status`.
* `flutter run -d web-server --release` rebuilt `build/web` but copied the existing stale `web/pkg` output.
* The white screen is reproducible even when `index.html`, `pkg/rust_lib_rss_reader.js`, and `pkg/rust_lib_rss_reader_bg.wasm` all return HTTP 200 with correct COOP/COEP headers.
