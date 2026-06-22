# RSS Reader

一个基于 `Flutter + Rust + flutter_rust_bridge` 的跨平台 RSS Reader MVP。

## 当前能力

- 手动添加 RSS / Atom feed
- Feed 列表
- 文章列表
- 文章详情
- 已读 / 未读切换
- 星标文章视图
- 刷新 feed
- 本地持久化订阅和文章状态

## 架构

- Flutter:
  - UI / 导航 / 交互
  - 网络请求
  - 本地持久化
- Rust:
  - Reader domain model
  - Snapshot 状态变更
  - RSS / Atom XML 解析
- Flutter 与 Rust 之间通过 `flutter_rust_bridge` 通信
- 跨层契约采用 `snapshot_json`：
  - Flutter 保存快照字符串
  - Rust 接收快照并返回新的快照

## 运行

### Linux

```bash
flutter run -d linux
```

### Android

```bash
flutter emulators
flutter emulators --launch <id>
flutter run -d <android-device-id>
```

## 本地打包

本地脚本默认使用 `tools/flutter`。如需指定其他 Flutter 可执行文件，可设置 `FLUTTER_BIN=/path/to/flutter`。

### Android

构建 release APK 和 release AAB：

```bash
./tools/build-android
```

可追加 Flutter build 参数，例如：

```bash
./tools/build-android --build-name 1.0.0 --build-number 1
```

产物位置：

- APK: `build/app/outputs/flutter-apk/app-release.apk`
- Unsigned APK copy, when signing is not configured: `build/app/outputs/apk/release/app-release-unsigned.apk`
- AAB: `build/app/outputs/bundle/release/`

Release 签名是可选启用的。本地需要正式签名时：

```bash
cp android/key.properties.example android/key.properties
```

然后编辑 `android/key.properties`，并把 keystore 文件放到对应的 `storeFile` 路径。`android/key.properties`、`*.jks`、`*.keystore` 已被 `android/.gitignore` 忽略，不要提交签名材料。

也可以使用环境变量启用签名：

```bash
ANDROID_KEYSTORE_PATH=/absolute/path/to/upload-keystore.jks \
ANDROID_KEYSTORE_PASSWORD=... \
ANDROID_KEY_ALIAS=upload \
ANDROID_KEY_PASSWORD=... \
./tools/build-android
```

如果没有配置签名材料，脚本仍会构建 release artifacts，但不会把 release 构建绑定到 debug key。

### Linux

构建 Flutter Linux release bundle，并压缩为 tarball：

```bash
./tools/build-linux-bundle
```

默认产物：

```bash
dist/rss_reader-linux-x64.tar.gz
```

可通过环境变量调整输出目录和文件名：

```bash
DIST_DIR=dist LINUX_ARCHIVE_NAME=rss_reader-linux.tar.gz ./tools/build-linux-bundle
```

Linux 本地打包需要 Flutter Linux 桌面构建依赖，例如 `clang`、`cmake`、`ninja-build`、`pkg-config`、`libgtk-3-dev`，以及本项目 Rust/Cargo 构建环境。

### Linux AppImage

构建 AppImage 需要额外提供 `appimagetool`：

```bash
./tools/build-linux-appimage
```

如果 `appimagetool` 不在 `PATH` 中，可显式指定：

```bash
APPIMAGETOOL=/path/to/appimagetool ./tools/build-linux-appimage
```

默认产物：

```bash
dist/RSS_Reader-x86_64.AppImage
```

可通过环境变量调整输出文件名：

```bash
APPIMAGE_NAME=RSS_Reader.AppImage ./tools/build-linux-appimage
```

脚本会复用 `./tools/build-linux-bundle`，然后生成 AppDir 并调用 `appimagetool`。Omarchy / Arch 上运行 AppImage 时，如果缺少 FUSE 支持，可安装：

```bash
omarchy pkg install fuse2
```

### Web

Rust / FRB code changes need a web artifact rebuild before running Flutter on web:

```bash
./tools/rebuild-web
```

本地调试：

```bash
flutter run -d web-server \
  --web-header=Cross-Origin-Opener-Policy=same-origin \
  --web-header=Cross-Origin-Embedder-Policy=require-corp
```

Chrome 调试：

```bash
flutter run -d chrome \
  --web-header=Cross-Origin-Opener-Policy=same-origin \
  --web-header=Cross-Origin-Embedder-Policy=require-corp
```

生产构建：

```bash
./tools/rebuild-web
flutter build web
```

### Web Docker

Build a local Web image:

```bash
./tools/build-web-image
```

Run the image locally on `http://127.0.0.1:8080`:

```bash
./tools/run-web-image
```

Use a different local port or image tag if needed:

```bash
./tools/build-web-image my-rss-reader-web
./tools/run-web-image 9090 my-rss-reader-web
```

The containerized nginx runtime serves the built Flutter Web bundle with:

- `Cross-Origin-Opener-Policy: same-origin`
- `Cross-Origin-Embedder-Policy: require-corp`

This prevents the FRB Web worker / wasm initialization regressions seen during local debugging and deployment verification.

Important limitation:

- Docker fixes build reproducibility and response headers.
- It does **not** fix browser-side RSS feed CORS restrictions.
- The current Web app fetches feed URLs directly from the browser in `ReaderRepository`, so some feeds may still fail on Web even if the container is configured correctly.

## 验证

Rust:

```bash
cargo test --manifest-path rust/Cargo.toml --offline
```

Flutter:

```bash
flutter analyze
flutter test integration_test/simple_test.dart
```

## 参考

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- `doc/oksskolten` 仅作为产品交互参考
