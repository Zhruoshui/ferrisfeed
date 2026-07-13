# Official Packaging Docs Research

## Sources

* Flutter Android deployment: https://docs.flutter.dev/deployment/android
* Flutter Linux deployment: https://docs.flutter.dev/deployment/linux
* Flutter continuous deployment: https://docs.flutter.dev/deployment/cd
* GitHub Actions artifact docs: https://docs.github.com/en/actions/how-tos/writing-workflows/choosing-what-your-workflow-does/storing-and-sharing-data-from-a-workflow
* GitHub-hosted Ubuntu 24.04 runner image docs: https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md
* `subosito/flutter-action`: https://github.com/subosito/flutter-action

## Findings

* Flutter's Android release path supports both APK and Android App Bundle outputs. AAB is the Play Store-oriented artifact; APK is useful for direct installation and smoke testing.
* Flutter's Android release docs expect a release signing setup for production artifacts. This repo currently signs `release` with the debug signing config, so production packaging needs a keystore-backed signing path.
* Flutter's Linux release path produces a release bundle. Distribution-specific package formats such as AppImage, deb, Snap, or Flatpak add metadata and toolchain requirements on top of that bundle.
* Flutter's CD docs describe using automation around the same build outputs rather than a separate build model. Local commands and CI commands should therefore share script wrappers where practical.
* GitHub Actions artifact upload/download is the right first step for downloadable CI build outputs before store publishing.
* GitHub-hosted Ubuntu runners are a reasonable base for Linux and Android packaging, but this project also needs Rust/Cargo and Linux GTK/CMake/Ninja dependencies because of Flutter Linux and Cargokit.
* `subosito/flutter-action` is the common GitHub Actions setup path for Flutter SDK installation, but it is a community action rather than a Flutter-owned action. If avoiding third-party actions is important, CI can install Flutter manually instead.

## Mapping to this repo

* Recommended Android MVP artifact set: release APK + release AAB.
* Recommended Linux MVP artifact set: raw Flutter release bundle archived as a `.tar.gz`.
* Defer AppImage/deb/Flatpak until the raw Linux bundle builds reliably in CI.
* Add signing as a separate Android step: local debug/unsigned path first, then release signing through environment variables or GitHub Actions secrets.
* Make `tools/flutter` portable before CI relies on scripts, or have CI call `flutter` directly after setup.
