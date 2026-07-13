# Test FVM Setup

## Goal

Verify that this Flutter/Rust project can be used through FVM instead of the native Flutter SDK, and document any local setup issues found during validation.

## What I Already Know

* The user installed FVM and wants this project tested with it.
* The repository currently has no project-level `.fvm/` directory or `.fvmrc`.
* FVM is installed at `/home/ruoshui/fvm/bin/fvm`, version `4.1.1`.
* The current non-interactive shell cannot find `fvm` via `PATH`.
* FVM has no Flutter SDKs installed yet.
* The native Flutter SDK reports `Flutter 3.44.1` with `Dart 3.12.1`.
* `pubspec.yaml` requires Dart `^3.12.1`, and project notes mention using FVM with Flutter `3.44.1`.
* Packaging scripts default to `tools/flutter`, but allow overriding with `FLUTTER_BIN=/path/to/flutter`.

## Requirements

* Use Flutter `3.44.1` as the intended FVM-managed SDK for this project.
* Configure or verify project-level FVM usage.
* Run the normal project validation commands through FVM where feasible:
  * `fvm flutter --version`
  * `fvm flutter doctor`
  * `fvm flutter pub get`
  * `fvm flutter analyze`
  * `fvm flutter test`
  * `FLUTTER_BIN=.fvm/flutter_sdk/bin/flutter ./tools/build-linux-bundle`
* Record any blocker caused by local PATH, network, SDK cache, or host toolchain setup.

## Acceptance Criteria

* [x] FVM command is runnable.
* [x] Flutter `3.44.1` is available through FVM.
* [x] Project dependency resolution is tested through FVM.
* [x] Analyzer/test status is recorded through FVM.
* [x] Linux bundle packaging is tested through the FVM SDK.
* [x] No unrelated application code is changed.

## Definition of Done

* FVM setup outcome is summarized for the user.
* Any commands that failed are reported with the actionable cause.
* Git dirty state is reviewed before wrap-up.

## Out of Scope

* Changing application behavior.
* Reworking packaging scripts unless FVM validation reveals a required minimal fix.
* Installing Android emulator images or debugging device-specific runtime issues.

## Technical Notes

* `README.md` validation section lists `flutter analyze` and `flutter test integration_test/simple_test.dart`.
* `tools/build-linux-bundle` and `tools/build-android` support `FLUTTER_BIN` overrides.
* Native Flutter lives at `/home/ruoshui/Documents/flutter/flutter/bin/flutter`.
* Project FVM config now pins Flutter `3.44.1` in `.fvmrc`.
* `.fvm/` is ignored as local SDK cache/symlink state.
* Interactive bash can find `/home/ruoshui/fvm/bin/fvm`; the Codex non-interactive shell did not inherit that path.
* Bare `flutter` still resolves to the native SDK in the user's interactive shell; use `fvm flutter ...` for project-pinned commands.
* `flutter doctor -v` through FVM reports one issue: Chrome executable `google-chrome` is missing, which affects Chrome Web debugging only.
* README still mentions `integration_test/simple_test.dart`, but the current test files live under `test/`; validation used `fvm flutter test`.
