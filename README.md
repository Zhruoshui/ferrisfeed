# FerrisFeed

<p align="center">
  <img src="images/logo.png" alt="FerrisFeed logo" width="420">
</p>

<p align="center">
  中文 | <a href="README.en.md">English</a>
</p>

FerrisFeed 是一个基于 Flutter、Rust 和 `flutter_rust_bridge` 构建的跨平台
RSS / Atom 阅读器。Flutter 负责界面、平台能力和本地交互，Rust 负责 feed
领域模型、状态流转和 RSS / Atom XML 解析。

## 当前能力

- 手动添加 RSS / Atom feed
- 浏览订阅列表
- 浏览文章列表
- 查看文章详情
- 切换已读 / 未读状态
- 星标文章
- 刷新 feed
- 本地持久化订阅和文章状态

## 架构

| 层 | 职责 |
| --- | --- |
| Flutter | UI、导航、交互、HTTP 请求、本地持久化 |
| Rust | Reader 领域模型、snapshot 状态流转、RSS / Atom XML 解析 |
| flutter_rust_bridge | Dart / Rust 边界和生成绑定 |

跨层状态契约是 `snapshot_json`：

- Flutter 保存 snapshot 字符串。
- Rust 接收旧 snapshot，并返回新的 snapshot。

## 工具链

项目使用 FVM 锁定 Flutter 版本：

```bash
fvm flutter --version
```

当前版本：

```text
Flutter 3.44.1
Dart 3.12.1
```

直接运行 Flutter 命令时，优先使用：

```bash
fvm flutter ...
```

项目打包脚本如果支持 `FLUTTER_BIN`，需要传入 FVM 管理的 Flutter 可执行文件路径：

```bash
FLUTTER_BIN=.fvm/flutter_sdk/bin/flutter <script>
```

## 本地运行

安装依赖：

```bash
fvm flutter pub get
```

运行 Linux 桌面版：

```bash
fvm flutter run -d linux
```

运行 Android：

```bash
fvm flutter devices
fvm flutter run -d <android-device-id>
```

运行 Web server，并带上 FRB Web worker / wasm 所需的跨源隔离响应头：

```bash
./tools/rebuild-web
fvm flutter run -d web-server \
  --web-header=Cross-Origin-Opener-Policy=same-origin \
  --web-header=Cross-Origin-Embedder-Policy=require-corp
```

## 验证

Flutter：

```bash
fvm flutter analyze
fvm flutter test
```

Rust：

```bash
cargo test --manifest-path rust/Cargo.toml --offline
```

## 构建与打包

### Android

使用 FVM 锁定的 SDK 构建 release APK 和 AAB：

```bash
FLUTTER_BIN=.fvm/flutter_sdk/bin/flutter ./tools/build-android
```

产物位置：

- `build/app/outputs/flutter-apk/app-release.apk`
- `build/app/outputs/apk/release/app-release.apk`
- `build/app/outputs/bundle/release/app-release.aab`

可追加版本信息：

```bash
FLUTTER_BIN=.fvm/flutter_sdk/bin/flutter \
  ./tools/build-android --build-name 1.0.0 --build-number 1
```

当存在 `android/key.properties` 或对应环境变量时，release 签名会自动启用。
本地签名文件已被 Git 忽略。

配置本地签名：

```bash
cp android/key.properties.example android/key.properties
```

然后编辑 `android/key.properties`，并把 keystore 放到 `storeFile` 指向的位置。

也可以使用环境变量签名：

```bash
ANDROID_KEYSTORE_PATH=/absolute/path/to/upload-keystore.jks \
ANDROID_KEYSTORE_PASSWORD=... \
ANDROID_KEY_ALIAS=upload \
ANDROID_KEY_PASSWORD=... \
FLUTTER_BIN=.fvm/flutter_sdk/bin/flutter \
./tools/build-android
```

快速安装 debug 包到手机：

```bash
fvm flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

如果 `adb` 不在 `PATH` 中，请使用 Android SDK `platform-tools` 目录里的
`adb` 可执行文件。

### Linux Bundle

构建 Flutter Linux release bundle，并压缩为 tarball：

```bash
FLUTTER_BIN=.fvm/flutter_sdk/bin/flutter ./tools/build-linux-bundle
```

默认产物：

```text
dist/rss_reader-linux-x64.tar.gz
```

自定义输出：

```bash
DIST_DIR=dist \
LINUX_ARCHIVE_NAME=ferrisfeed-linux-x64.tar.gz \
FLUTTER_BIN=.fvm/flutter_sdk/bin/flutter \
./tools/build-linux-bundle
```

Linux 打包需要 Flutter Linux 桌面构建依赖，例如 `clang`、`cmake`、
`ninja-build`、`pkg-config`、`libgtk-3-dev`，以及本项目 Rust / Cargo 环境。

### Linux AppImage

构建 AppImage：

```bash
FLUTTER_BIN=.fvm/flutter_sdk/bin/flutter ./tools/build-linux-appimage
```

默认产物：

```text
dist/RSS_Reader-x86_64.AppImage
```

如果 `appimagetool` 不在 `PATH` 中，可以显式指定：

```bash
APPIMAGETOOL=/path/to/appimagetool \
FLUTTER_BIN=.fvm/flutter_sdk/bin/flutter \
./tools/build-linux-appimage
```

Omarchy / Arch 上运行 AppImage 时，如果缺少 FUSE 2：

```bash
omarchy pkg install fuse2
```

### Web

Rust / FRB 相关代码变更后，验证 Web 前需要重建 Web artifacts：

```bash
./tools/rebuild-web
fvm flutter build web
```

### Web Docker

构建本地 Web 镜像：

```bash
./tools/build-web-image ferrisfeed-web
```

本地运行镜像：

```bash
./tools/run-web-image 8080 ferrisfeed-web
```

nginx runtime 会为 Flutter Web 提供：

- `Cross-Origin-Opener-Policy: same-origin`
- `Cross-Origin-Embedder-Policy: require-corp`

这些响应头用于避免 FRB Web worker / wasm 初始化阶段的白屏问题。

注意：Docker 构建不使用宿主机的 FVM。它通过 `Dockerfile.web` 里的
`FLUTTER_REVISION` 固定 Flutter 版本，因此该 revision 需要与 `.fvmrc` 保持一致。

## Web 限制

Docker 能提高构建可复现性并保证响应头，但不能解决浏览器侧 RSS feed CORS
限制。当前 Web 应用直接在浏览器中请求 feed URL，因此即使 Docker runtime 配置正确，
部分 feed 在 Web 端仍可能失败。

## 维护提示

- 提交 `.fvmrc`。
- 不要提交 `.fvm/`、签名密钥、`android/key.properties`、`build/` 或 `dist/`。
- Rust / FRB API 影响 Web 时，记得运行 `./tools/rebuild-web`。
- 保持 `Dockerfile.web` 的 Flutter revision 与 `.fvmrc` 一致。
- 妥善备份 Android release 签名材料；同一包名后续更新必须使用同一个 keystore。

## 参考

- [Flutter documentation](https://docs.flutter.dev/)
- [flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge)
