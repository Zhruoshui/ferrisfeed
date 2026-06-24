# FerrisFeed

<p align="center">
  <img src="images/logo.png" alt="FerrisFeed logo" width="420">
</p>

<p align="center">
  <a href="README.md">中文</a> | English
</p>

FerrisFeed is a cross-platform RSS/Atom reader built with Flutter, Rust, and
`flutter_rust_bridge`. Flutter owns the UI and platform shell, while Rust owns
the feed/domain model and parsing logic.

## Features

- Add RSS / Atom feeds manually
- Browse feed subscriptions
- Browse article lists
- Read article details
- Toggle read / unread state
- Star articles
- Refresh feeds
- Persist subscriptions and article state locally

## Architecture

| Layer | Responsibility |
| --- | --- |
| Flutter | UI, navigation, user interaction, HTTP fetches, local persistence |
| Rust | Reader domain model, snapshot state transitions, RSS / Atom XML parsing |
| flutter_rust_bridge | Dart/Rust boundary and generated bindings |

The cross-layer state contract is `snapshot_json`:

- Flutter stores the snapshot string.
- Rust receives the previous snapshot and returns the next snapshot.

## Toolchain

This project is pinned with FVM:

```bash
fvm flutter --version
```

Current pin:

```text
Flutter 3.44.1
Dart 3.12.1
```

For direct Flutter commands, prefer:

```bash
fvm flutter ...
```

For project packaging scripts that accept `FLUTTER_BIN`, pass the executable
path managed by FVM:

```bash
FLUTTER_BIN=.fvm/flutter_sdk/bin/flutter <script>
```

## Run Locally

Install dependencies:

```bash
fvm flutter pub get
```

Run on Linux desktop:

```bash
fvm flutter run -d linux
```

Run on Android:

```bash
fvm flutter devices
fvm flutter run -d <android-device-id>
```

Run on Web server with the headers required by the FRB Web worker / wasm
runtime:

```bash
./tools/rebuild-web
fvm flutter run -d web-server \
  --web-header=Cross-Origin-Opener-Policy=same-origin \
  --web-header=Cross-Origin-Embedder-Policy=require-corp
```

## Validate

Flutter checks:

```bash
fvm flutter analyze
fvm flutter test
```

Rust checks:

```bash
cargo test --manifest-path rust/Cargo.toml --offline
```

## Build And Package

### Android

Build release APK and AAB with the FVM-pinned SDK:

```bash
FLUTTER_BIN=.fvm/flutter_sdk/bin/flutter ./tools/build-android
```

Artifacts:

- `build/app/outputs/flutter-apk/app-release.apk`
- `build/app/outputs/apk/release/app-release.apk`
- `build/app/outputs/bundle/release/app-release.aab`

Optional build metadata:

```bash
FLUTTER_BIN=.fvm/flutter_sdk/bin/flutter \
  ./tools/build-android --build-name 1.0.0 --build-number 1
```

Release signing is enabled when `android/key.properties` or the matching
environment variables are present. Local signing files are ignored by Git.

To configure local signing:

```bash
cp android/key.properties.example android/key.properties
```

Then edit `android/key.properties` and place the keystore at the configured
`storeFile` path.

Environment-variable signing is also supported:

```bash
ANDROID_KEYSTORE_PATH=/absolute/path/to/upload-keystore.jks \
ANDROID_KEYSTORE_PASSWORD=... \
ANDROID_KEY_ALIAS=upload \
ANDROID_KEY_PASSWORD=... \
FLUTTER_BIN=.fvm/flutter_sdk/bin/flutter \
./tools/build-android
```

For quick device verification with a debug build:

```bash
fvm flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

If `adb` is not on `PATH`, use the `adb` binary from your Android SDK
`platform-tools` directory.

### Linux Bundle

Build a Flutter Linux release bundle and archive it as a tarball:

```bash
FLUTTER_BIN=.fvm/flutter_sdk/bin/flutter ./tools/build-linux-bundle
```

Default artifact:

```text
dist/rss_reader-linux-x64.tar.gz
```

Custom output:

```bash
DIST_DIR=dist \
LINUX_ARCHIVE_NAME=ferrisfeed-linux-x64.tar.gz \
FLUTTER_BIN=.fvm/flutter_sdk/bin/flutter \
./tools/build-linux-bundle
```

Linux packaging requires Flutter Linux desktop build dependencies such as
`clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`, plus this
project's Rust/Cargo toolchain.

### Linux AppImage

Build an AppImage:

```bash
FLUTTER_BIN=.fvm/flutter_sdk/bin/flutter ./tools/build-linux-appimage
```

Default artifact:

```text
dist/RSS_Reader-x86_64.AppImage
```

If `appimagetool` is not on `PATH`, pass it explicitly:

```bash
APPIMAGETOOL=/path/to/appimagetool \
FLUTTER_BIN=.fvm/flutter_sdk/bin/flutter \
./tools/build-linux-appimage
```

On Omarchy / Arch, AppImage runtime execution may require FUSE 2:

```bash
omarchy pkg install fuse2
```

### Web

Rust / FRB changes require a Web artifact rebuild before validating Web:

```bash
./tools/rebuild-web
fvm flutter build web
```

### Web Docker

Build a local Web image:

```bash
./tools/build-web-image ferrisfeed-web
```

Run the image locally:

```bash
./tools/run-web-image 8080 ferrisfeed-web
```

The nginx runtime serves Flutter Web with:

- `Cross-Origin-Opener-Policy: same-origin`
- `Cross-Origin-Embedder-Policy: require-corp`

These headers prevent FRB Web worker / wasm initialization regressions during
deployment verification.

Important detail: the Docker build does not use the host FVM binary. It pins
Flutter through `Dockerfile.web`'s `FLUTTER_REVISION`, which should remain in
sync with `.fvmrc`.

## Web Limitations

Docker improves build reproducibility and response headers, but it does not
remove browser-side RSS feed CORS restrictions. The current Web app fetches
feed URLs directly from the browser, so some feeds may still fail on Web even
when the Docker runtime is configured correctly.

## Notes For Maintainers

- Commit `.fvmrc`.
- Do not commit `.fvm/`, signing keys, `android/key.properties`, `build/`, or
  `dist/`.
- Run `./tools/rebuild-web` after Rust / FRB API changes that affect Web.
- Keep `Dockerfile.web`'s Flutter revision aligned with `.fvmrc`.
- Keep release signing material backed up; future signed Android updates must
  use the same keystore.

## References

- [Flutter documentation](https://docs.flutter.dev/)
- [flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge)
