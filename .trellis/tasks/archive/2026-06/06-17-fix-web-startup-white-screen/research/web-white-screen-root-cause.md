# Web White Screen Root Cause

## Summary

The current web white screen is caused by stale Flutter Rust Bridge web artifacts in `web/pkg`, not by the earlier `DataCloneError` bug and not by missing COOP/COEP headers.

## Reproduction

Command used:

```bash
flutter run -d web-server --release --web-hostname 127.0.0.1 --web-port 7358 --web-header=Cross-Origin-Opener-Policy=same-origin --web-header=Cross-Origin-Embedder-Policy=require-corp
```

Observed:

* `build/web` compiled successfully.
* `http://127.0.0.1:7358/` returned 200.
* `pkg/rust_lib_rss_reader.js` returned 200.
* `pkg/rust_lib_rss_reader_bg.wasm` returned 200 with `content-type: application/wasm`.
* COOP/COEP headers were present.
* Headless Chromium screenshot was pure white.

Captured CDP exception:

```text
Bad state: Content hash on Dart side (-1008744160) is different from Rust side (-1918914929), indicating out-of-sync code.
```

## Relevant Code Path

`lib/main.dart` waits for bootstrap before rendering:

```dart
Future<void> main() async {
  final controller = await bootstrapReaderController();
  runApp(MyApp(controller: controller));
}
```

`bootstrapReaderController()` calls `await RustLib.init()` before `runApp()`. Any uncaught failure there prevents Flutter from mounting the UI, so the browser stays white.

## Hash Evidence

Current checked/generated bridge files agree:

```text
rust/src/frb_generated.rs:
FLUTTER_RUST_BRIDGE_CODEGEN_CONTENT_HASH = -1008744160

lib/src/rust/frb_generated.dart:
rustContentHash => -1008744160
```

The loaded web WASM reports:

```text
Rust side = -1918914929
```

File timestamps show the likely drift:

```text
web/pkg/rust_lib_rss_reader_bg.wasm       2026-06-16 16:01
lib/src/rust/frb_generated.dart           2026-06-17 11:58
rust/src/frb_generated.rs                 2026-06-17 11:11
build/web/pkg/rust_lib_rss_reader_bg.wasm 2026-06-17 16:19
```

`build/web/pkg` is copied from stale `web/pkg`; `flutter build web` does not regenerate the FRB WASM artifact.

## Why Linux and Android Can Still Work

Linux and Android build native Rust artifacts through the platform build integration, so they can be using current Rust source even while web keeps loading an older static WASM artifact from `web/pkg`.

## Relation to `doc/ref/web-platform-fix.md`

The previous fix addressed FRB web worker initialization by using `flutter_rust_bridge` git rev `254b193`.

Current state:

* `pubspec.yaml` uses `flutter_rust_bridge` git ref `254b193`.
* `rust/Cargo.toml` uses `flutter_rust_bridge` git rev `254b193`.
* The installed FRB runtime contains the fixed web loader that calls `wasmBindgen('${root}_bg.wasm'.toJS)`.
* The current failure is a stale-artifact mismatch after codegen/source changes, not the old `DataCloneError`.

## Recommended Fix Path

1. Run `flutter_rust_bridge_codegen generate` if bridge inputs changed or generated files are suspect.
2. Run `flutter_rust_bridge_codegen build-web` to rebuild `web/pkg`.
3. Re-run release web-server with COOP/COEP headers.
4. Verify browser console no longer reports content hash mismatch.
5. Capture a headless Chromium screenshot showing the app UI.

## Follow-Up Guardrail

Because `web/pkg` is ignored, this class of bug can recur invisibly. A useful follow-up is a documented command or script that rebuilds/checks FRB web artifacts whenever Rust APIs or generated bridge files change.
