# Android and Linux Packaging

## Goal

Define how to package the Flutter + Rust RSS Reader locally for Android and Linux, then leave GitHub Actions as a follow-up once the local packaging contract is stable.

## What I already know

* The app is a Flutter + Rust + flutter_rust_bridge project.
* Existing README documents local run commands for Linux, Android, and Web.
* Existing `tools/` scripts only cover Web rebuild and Docker image workflows.
* Android and Linux are both enabled through the `rust_lib_rss_reader` FFI plugin in `rust_builder/pubspec.yaml`.
* Android release builds previously used the debug signing config.
* Android still uses the template application id `com.example.rss_reader`.
* Linux currently uses the default Flutter relocatable bundle output.
* There is no `.github/` workflow directory yet.

## Assumptions (temporary)

* Packaging should prioritize reproducible artifacts before public store publishing.
* GitHub Actions should be considered after local commands are stable.
* Android signing secrets, if needed, will be provided through GitHub Actions secrets and not committed.

## Open Questions

* None for the local packaging MVP.

## Requirements (evolving)

* Provide a documented local packaging path for Android release APK and release AAB.
* Provide a documented local packaging path for a Linux release bundle archived as `.tar.gz`.
* Provide a documented local packaging path for a Linux AppImage built from the release bundle.
* Keep future CI packaging aligned with local commands.
* Account for Rust/Cargokit build requirements on both platforms.
* Avoid committing signing keys or machine-local SDK paths.
* Prepare Android release signing, but enable it only when local signing config exists.
* Do not continue using the debug signing config for release artifacts.

## Acceptance Criteria (evolving)

* [x] A maintainer can build Android release APK and AAB artifacts locally with one documented command path.
* [x] A maintainer can build a Linux release bundle archive locally with one documented command path.
* [x] A maintainer can build a Linux AppImage locally with one documented command path when `appimagetool` is available.
* [x] Packaging choices are explicit, including artifact paths and signing behavior.
* [x] Android release signing can be enabled without committing keystores or passwords.
* [x] Release builds clearly distinguish unsigned/test artifacts from signed release artifacts.
* [x] Secrets and local machine paths are not required in the repository.

## Definition of Done

* Tests or build verification added/updated where appropriate.
* Lint/typecheck/build commands are documented or automated.
* Future CI design can reuse the local packaging commands.
* Rollback is simple: packaging scripts/workflows can be removed without changing app runtime behavior.

## Out of Scope (explicit)

* Publishing to Google Play in the first iteration unless explicitly chosen.
* Publishing Linux packages to Flathub, Snapcraft, or distro repositories in the first iteration unless explicitly chosen.
* iOS, macOS, Windows packaging.
* GitHub Actions workflow implementation in the local packaging MVP.

## Technical Notes

* `pubspec.yaml` declares `version: 1.0.0+1`; Flutter build flags can override build name/number.
* `android/app/build.gradle.kts` no longer binds release builds to the debug signing config.
* `android/settings.gradle.kts` depends on `android/local.properties` for local Flutter SDK discovery.
* `linux/CMakeLists.txt` installs a relocatable bundle under Flutter's Linux build output.
* `tools/flutter` points at a local absolute Flutter SDK path, so CI should not rely on it unless the script is made portable.
* `./tools/flutter doctor -v` failed in the Codex sandbox because the external Flutter SDK cache directory is read-only.
* Implemented local Android packaging through `tools/build-android`.
* Implemented local Linux bundle packaging through `tools/build-linux-bundle`.
* Implemented local Linux AppImage packaging through `tools/build-linux-appimage`.
* Verified `tools/build-android` builds `build/app/outputs/flutter-apk/app-release.apk`, `build/app/outputs/apk/release/app-release-unsigned.apk`, and `build/app/outputs/bundle/release/app-release.aab`.
* Verified `tools/build-linux-bundle` builds `dist/rss_reader-linux-x64.tar.gz`.
* Verified `tools/build-linux-appimage` builds `dist/RSS_Reader-x86_64.AppImage`.

## Initial Packaging Options

### Android

**Option A: APK first**

* Build `flutter build apk --release`.
* Lowest friction for manual installation and smoke testing.
* Not the preferred artifact for Google Play.

**Option B: AAB first**

* Build `flutter build appbundle --release`.
* Best aligned with Google Play.
* Less convenient for direct manual installation.

**Option C: APK + AAB** (recommended)

* Build both release APK and release AAB.
* APK supports direct testing; AAB keeps store path open.
* Requires signing decision before true release readiness.

### Linux

**Option A: Raw Flutter bundle** (recommended first step)

* Use `flutter build linux --release` and archive `build/linux/x64/release/bundle`.
* Lowest moving parts and best first CI target.
* Not as user-friendly as AppImage/deb/Flatpak.

**Option B: AppImage**

* Package the release bundle into a portable executable.
* Better for end-user download outside package managers.
* Adds app metadata, icon, desktop file, and packaging toolchain requirements.

**Option C: Debian package / Flatpak**

* Better for Linux distribution-style installs.
* More metadata and maintenance burden.
* Flatpak is strong for sandboxed desktop distribution but usually deserves a dedicated pass.

## Research References

* [`research/official-packaging-docs.md`](research/official-packaging-docs.md) — official Flutter/GitHub docs support APK+AAB for Android, raw Linux bundle first, artifact upload before store publishing.

## Recommended MVP Direction

* Android: build both release APK and release AAB, but treat production signing as an explicit step rather than continuing to use the debug signing config.
* Linux: first produce and archive the raw Flutter release bundle as `.tar.gz`, then package the same release bundle as AppImage for Omarchy/desktop installation.
* CI: deferred until local packaging commands are stable.

## Android Signing Decision

**Context**: The current Android `release` build uses the debug signing config, which makes release artifacts easy to install but unsafe to treat as deployable output.

**Decision**: Prepare a release signing path that activates only when signing material is provided locally. Default builds should not silently rely on the debug key for release artifacts.

**Consequences**: Local unsigned/test artifacts can still be built before signing material is configured, but signed production artifacts require explicit signing setup. This keeps the workflow usable early without weakening release semantics.

## Decision (ADR-lite)

**Context**: Android and Linux have multiple valid packaging outputs. The project needs a reliable local build contract before adding CI, store, or Linux package-manager publishing.

**Decision**: Use release APK + release AAB for Android, and produce both a compressed raw Flutter release bundle and an AppImage for Linux.

**Consequences**: Android remains compatible with direct smoke testing and future Play Store distribution. Linux keeps the raw bundle as the base artifact and adds AppImage for easier desktop installation; deb/Flatpak remain deferred.
