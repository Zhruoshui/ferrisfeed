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

Run the Windows desktop build:

```bash
fvm flutter run -d windows
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

### Windows

Build a Windows release:

```bash
fvm flutter config --enable-windows-desktop
fvm flutter build windows --release
```

Output location:

```text
build/windows/x64/runner/Release/
```

Windows builds require Visual Studio (with the "Desktop development with C++"
workload) plus this project's Rust / Cargo environment. CI on `windows-latest`
packages that directory as `ferrisfeed-<version>-windows-x64.zip`.

## Notes For Maintainers

- Commit `.fvmrc`.
- Do not commit `.fvm/`, signing keys, `android/key.properties`, `build/`, or
  `dist/`.
- Keep release signing material backed up; future signed Android updates must
  use the same keystore.

## References

- [Flutter documentation](https://docs.flutter.dev/)
- [flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge)
