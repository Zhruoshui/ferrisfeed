# Quality Guidelines

> Code quality standards for frontend development.

---

## Overview

Flutter web changes that depend on Flutter Rust Bridge must keep generated Dart/Rust code and `web/pkg` in sync. `flutter build web` and `flutter run -d web-server` do not regenerate the FRB wasm package.

---

## Forbidden Patterns

### Don't: Verify web changes without rebuilding FRB wasm

If `rust/src/api/*`, `rust/Cargo.toml`, `lib/src/rust/*`, or FRB config changes, do not leave `web/pkg` stale.

**Why it's bad**: `RustLib.init()` can fail before `runApp()` when Dart/Rust hashes drift from the loaded wasm artifact, producing a white screen.

---

## Required Patterns

### Rebuild FRB web artifacts after Rust/API changes

Use:

```bash
./tools/rebuild-web
```

This must run before validating Flutter web after FRB-related edits.

---

## Testing Requirements

- `flutter test`
- `flutter analyze`haod 
- Web startup verification with COOP/COEP headers

## Scenario: Local Android and Linux packaging

### 1. Scope / Trigger

- Trigger: packaging the Flutter + Rust app for local Android or Linux distribution.
- Applies when changes touch `tools/build-android`, `tools/build-linux-bundle`, `tools/build-linux-appimage`, `android/app/build.gradle.kts`, `android/key.properties.example`, local packaging docs, or Flutter/Rust native build inputs that affect Android/Linux artifacts.

### 2. Signatures

- Android: `./tools/build-android [flutter_build_flags...]`
- Linux: `./tools/build-linux-bundle [flutter_build_flags...]`
- Linux AppImage: `./tools/build-linux-appimage [flutter_build_flags...]`
- Linux output overrides:
  - `DIST_DIR=<dir>`
  - `LINUX_ARCHIVE_NAME=<name>.tar.gz`
  - `APPIMAGE_NAME=<name>.AppImage`
- Linux AppImage tool override:
  - `APPIMAGETOOL=/path/to/appimagetool`
- Android signing inputs:
  - `android/key.properties`
  - `ANDROID_KEYSTORE_PATH`
  - `ANDROID_KEYSTORE_PASSWORD`
  - `ANDROID_KEY_ALIAS`
  - `ANDROID_KEY_PASSWORD`

### 3. Contracts

- `tools/build-android` must run `flutter pub get`, `flutter build apk --release`, then `flutter build appbundle --release`.
- Android release builds must not use the debug signing config.
- Android release signing is enabled only when all signing fields are present through `android/key.properties` or environment variables.
- Android artifacts must include release APK and AAB outputs:
  - `build/app/outputs/flutter-apk/app-release.apk`
  - `build/app/outputs/apk/release/app-release-unsigned.apk` when signing is absent
  - `build/app/outputs/bundle/release/app-release.aab`
- `tools/build-linux-bundle` must run `flutter pub get`, `flutter build linux --release`, then archive `build/linux/x64/release/bundle` into `dist/rss_reader-linux-x64.tar.gz` by default.
- `tools/build-linux-appimage` must reuse `tools/build-linux-bundle`, copy the release bundle into an AppDir, create `AppRun`, create `rss_reader.desktop`, copy `web/icons/Icon-512.png`, and run `appimagetool`.
- Linux AppImage artifacts must default to `dist/RSS_Reader-x86_64.AppImage`.
- Generated packaging artifacts under `build/` and `dist/` must not be committed.

### 4. Validation & Error Matrix

- Missing Flutter SDK or invalid `FLUTTER_BIN` -> packaging script fails before artifact creation.
- Missing Android SDK/NDK -> Android build fails during Flutter/Gradle setup.
- Missing Rust Android targets -> Cargokit installs/builds targets or fails before APK/AAB output.
- Missing Linux GTK/CMake/Ninja/pkg-config dependencies -> Linux build fails before tarball creation.
- Missing `appimagetool` -> AppImage script fails with an explicit install/override message.
- Missing `web/icons/Icon-512.png` -> AppImage script fails before creating an invalid AppDir.
- Partial Android signing configuration -> release signing is not enabled; artifacts are unsigned/test outputs.
- Missing Linux bundle directory after build -> `tools/build-linux-bundle` exits non-zero instead of archiving an invalid path.

### 5. Good/Base/Bad Cases

- Good: `./tools/build-android` prints only release APK/AAB artifacts, `./tools/build-linux-bundle` prints a tarball under `dist/`, and `./tools/build-linux-appimage` prints an AppImage under `dist/`.
- Base: no signing material exists; Android artifacts build as unsigned/test release outputs without using the debug key.
- Bad: release builds silently use debug signing, `dist/` is tracked, the Android script reports stale debug artifacts, or AppImage packaging moves `rss_reader` away from its sibling `data/` and `lib/` directories.

### 6. Tests Required

- `bash -n tools/build-android`
- `bash -n tools/build-linux-bundle`
- `bash -n tools/build-linux-appimage`
- `./tools/build-android`
- `./tools/build-linux-bundle`
- `./tools/build-linux-appimage`
- `./tools/flutter analyze`
- `./tools/flutter test`
- `cargo test --manifest-path rust/Cargo.toml --offline`

### 7. Wrong vs Correct

#### Wrong

```kotlin
release {
    signingConfig = signingConfigs.getByName("debug")
}
```

This makes release outputs easy to install but weakens the meaning of a release artifact.

#### Correct

```kotlin
release {
    if (hasReleaseSigning) {
        signingConfig = signingConfigs.getByName("release")
    }
}
```

Release signing is explicit, and unsigned/test artifacts cannot be mistaken for debug-key release outputs.

---

## Scenario: Dockerized Flutter Web runtime

### 1. Scope / Trigger

- Trigger: packaging the Flutter Web build into a local nginx Docker runtime.
- Applies when Web deployment changes touch `Dockerfile.web`, `nginx/web.conf`, `tools/*web-image`, `flutter_rust_bridge.yaml`, or FRB-generated web artifacts.

### 2. Signatures

- Build image: `./tools/build-web-image [image_tag]`
- Run image: `./tools/run-web-image [host_port] [image_tag]`
- Underlying build: `docker build -f Dockerfile.web -t <image_tag> .`
- Underlying run: `docker run --rm -p <host_port>:80 <image_tag>`

### 3. Contracts

- Docker Web builds must run `flutter pub get`, `./tools/rebuild-web`, then `flutter build web` inside the builder stage.
- The builder stage must provide stable Rust plus nightly Rust with `rust-src` and the `wasm32-unknown-unknown` target; FRB Web uses nightly `-Z build-std`.
- Keep `auto_upgrade_dependency: false` in `flutter_rust_bridge.yaml`; do not use the invalid `no_auto_upgrade_dependency` key.
- Runtime nginx must serve `build/web` with `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp`.
- Static assets such as `.wasm`, `.js`, `.css`, `.json`, and images must return `404` when missing; do not SPA-fallback missing static assets to `index.html`.

### 4. Validation & Error Matrix

- Missing nightly `rust-src` -> `wasm-pack build ... -Z build-std` fails with `Cargo.lock does not exist`.
- Missing COOP/COEP headers -> FRB Web worker / wasm startup can fail before `runApp()`, producing a white screen.
- Missing static asset returns `index.html` -> browser receives HTML for wasm/js and startup fails.
- Invalid FRB config key -> `flutter_rust_bridge_codegen generate` fails before web build.

### 5. Good/Base/Bad Cases

- Good: image builds from a clean checkout and `curl -I /pkg/rust_lib_rss_reader_bg.wasm` returns `200` with `Content-Type: application/wasm`.
- Base: `/` returns `200` with both COOP/COEP headers.
- Bad: `/pkg/definitely-missing.wasm` returns `200` or `text/html`.

### 6. Tests Required

- `bash -n tools/build-web-image`
- `bash -n tools/run-web-image`
- `docker build -f Dockerfile.web -t <test_tag> .`
- `docker run -d --name <test_name> -p <port>:80 <test_tag>`
- `curl -I http://127.0.0.1:<port>/`
- `curl -I http://127.0.0.1:<port>/pkg/rust_lib_rss_reader_bg.wasm`
- `curl -I http://127.0.0.1:<port>/pkg/definitely-missing.wasm`

### 7. Wrong vs Correct

#### Wrong

```nginx
location / {
  try_files $uri $uri/ /index.html;
}
```

This fallback alone also catches missing `.wasm` and `.js` assets.

#### Correct

```nginx
location ~* \.(?:js|css|wasm|json|png|jpg|jpeg|gif|svg|ico)$ {
  try_files $uri =404;
}

location / {
  try_files $uri $uri/ /index.html;
}
```

---

## Scenario: FVM-pinned deployment validation

### 1. Scope / Trigger

- Trigger: validating local deployment artifacts while the project uses `.fvmrc`.
- Applies when changes touch `.fvmrc`, `.gitignore` FVM rules, `tools/build-android`, `tools/build-linux-bundle`, `tools/build-linux-appimage`, `tools/build-web-image`, `Dockerfile.web`, packaging docs, or Flutter/Rust build inputs.
- Current project pin: Flutter `3.44.1` with Dart `3.12.1`.

### 2. Signatures

- Check pinned SDK: `fvm flutter --version`
- Resolve dependencies: `fvm flutter pub get`
- Analyze: `fvm flutter analyze`
- Test: `fvm flutter test`
- Linux bundle through FVM: `FLUTTER_BIN=.fvm/flutter_sdk/bin/flutter ./tools/build-linux-bundle`
- Linux AppImage through FVM: `FLUTTER_BIN=.fvm/flutter_sdk/bin/flutter ./tools/build-linux-appimage`
- Android release through FVM: `FLUTTER_BIN=.fvm/flutter_sdk/bin/flutter ./tools/build-android`
- Web Docker image: `./tools/build-web-image <image_tag>`
- Web Docker smoke run: `docker run --rm -d --name <test_name> -p <host_port>:80 <image_tag>`
- Web Docker cleanup: `docker stop <test_name>`

### 3. Contracts

- `.fvmrc` is the project-level Flutter version pin and should be committed.
- `.fvm/` is local SDK cache/symlink state and must remain ignored.
- Direct Flutter commands should use `fvm flutter ...` to honor `.fvmrc`.
- Direct Dart commands should use `fvm dart ...` when the Dart SDK version matters.
- Packaging scripts that expose `FLUTTER_BIN` expect a single executable path, not a shell phrase; pass `.fvm/flutter_sdk/bin/flutter`, not `fvm flutter`.
- `tools/build-android`, `tools/build-linux-bundle`, and `tools/build-linux-appimage` can be validated against FVM by setting `FLUTTER_BIN=.fvm/flutter_sdk/bin/flutter`.
- `tools/build-web-image` does not consume host FVM. `Dockerfile.web` clones Flutter by `FLUTTER_REVISION`, so that revision must stay in sync with `.fvmrc`.
- `Dockerfile.web` may print `Has .fvmrc but no fvm binary installation, thus skip using fvm` from FRB codegen; this is acceptable only when `FLUTTER_REVISION` still matches the `.fvmrc` release.
- Generated deployment artifacts under `build/` and `dist/` must not be committed.

### 4. Validation & Error Matrix

- `fvm` is not on `PATH` -> use the known installed binary path or source the user's interactive shell config before running FVM commands.
- `.fvm/flutter_sdk` is missing -> run `fvm use 3.44.1 --force` from the repo root before script validation.
- `FLUTTER_BIN="fvm flutter"` -> scripts fail because they try to execute a non-path command string.
- `.fvmrc` changes but `Dockerfile.web` keeps the old `FLUTTER_REVISION` -> local FVM builds and Docker Web builds use different Flutter versions.
- Container lacks `fvm` and Dockerfile revision is stale -> FRB codegen skips FVM and the web image may build against the wrong Flutter revision.
- Docker container starts but sandbox `curl` cannot reach the published host port -> verify through a host browser and `docker logs`; this can be a sandbox networking limitation rather than a runtime failure.
- `flutter doctor` reports missing `google-chrome` -> Chrome Web debugging is unavailable, but Linux/Android packaging can still pass.

### 5. Good/Base/Bad Cases

- Good: FVM reports local Flutter `3.44.1`, Linux bundle and AppImage build through `FLUTTER_BIN=.fvm/flutter_sdk/bin/flutter`, Android APK/AAB build through the same FVM SDK, and the Web Docker image serves the app successfully.
- Base: Docker logs include Flutter root-user warnings, WebAssembly dry-run warnings, or FRB codegen "skip using fvm" messages, but the image build exits zero and the browser can load `/`, `main.dart.js`, and `/pkg/rust_lib_rss_reader_bg.wasm`.
- Bad: bare `flutter` is assumed to mean FVM, Dockerfile Flutter revision drifts from `.fvmrc`, `.fvm/` is committed, or a long-running test container is left running unintentionally.

### 6. Tests Required

- `fvm flutter --version`
- `fvm flutter pub get`
- `fvm flutter analyze`
- `fvm flutter test`
- `FLUTTER_BIN=.fvm/flutter_sdk/bin/flutter ./tools/build-linux-bundle`
- `FLUTTER_BIN=.fvm/flutter_sdk/bin/flutter ./tools/build-linux-appimage`
- `FLUTTER_BIN=.fvm/flutter_sdk/bin/flutter ./tools/build-android`
- `./tools/build-web-image <image_tag>`
- `docker run --rm -d --name <test_name> -p <host_port>:80 <image_tag>`
- Browser or HTTP verification of `http://127.0.0.1:<host_port>/`
- `docker stop <test_name>`

### 7. Wrong vs Correct

#### Wrong

```bash
./tools/build-android
./tools/build-linux-bundle
```

This relies on the scripts' default `tools/flutter` wrapper and does not prove the deployment path works through the FVM-pinned SDK.

#### Correct

```bash
FLUTTER_BIN=.fvm/flutter_sdk/bin/flutter ./tools/build-android
FLUTTER_BIN=.fvm/flutter_sdk/bin/flutter ./tools/build-linux-bundle
```

The scripts execute the Flutter binary symlinked by FVM for the current `.fvmrc` pin.

#### Wrong

```bash
FLUTTER_BIN="fvm flutter" ./tools/build-linux-bundle
```

`FLUTTER_BIN` is executed as a binary path, so this is not a valid command.

#### Correct

```bash
FLUTTER_BIN=.fvm/flutter_sdk/bin/flutter ./tools/build-linux-bundle
```

Use `fvm flutter ...` for direct commands, and use `.fvm/flutter_sdk/bin/flutter` when a script expects an executable path.

---

## Code Review Checklist

- `web/pkg` was rebuilt after FRB changes
- `uuid` wasm feature remains enabled for web builds
- FRB auto-upgrade stays disabled in `flutter_rust_bridge.yaml`
- Dockerized Web runtime preserves COOP/COEP headers and static asset 404 behavior
- `.fvmrc`, `.fvm/` ignore rules, and FVM command usage remain consistent
- `Dockerfile.web` Flutter revision remains in sync with the `.fvmrc` Flutter release
