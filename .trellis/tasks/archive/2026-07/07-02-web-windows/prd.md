# 移除 Web 端并聚焦 Android/Linux/Windows

## 背景

Web 端受浏览器 CORS 约束,几乎每个第三方 RSS 源都需要一个常驻的服务端 proxy 才能订阅,
带来永久性的后端维护与 SSRF 安全责任;叠加 localStorage 存储上限、WASM 包体、COOP/COEP
等逆风,Web 对一个 RSS 阅读器的体验天花板不高。决定砍掉 Web 构建产物,集中打磨
Android + Linux + Windows 三端。

FRB 多端共享架构本身保留(`feed_url -> xml_string -> Rust parser -> snapshot -> UI`),
以后若真需要 Web 可随时补回网络获取层,因此本次**只删 Web 构建/部署产物,不动共享架构**。

## 目标平台

- Android(保留,已有 CI)
- Linux 桌面(保留,已有 CI)
- Windows 桌面(新增 CI 构建,脚手架与 Rust/cargokit 集成已就绪)
- iOS / macOS:脚手架保留不动,不进 CI、不主动维护(用户决定)

## 范围

### 1. 删除 Web 构建 / 部署产物

- `web/` 目录(Flutter web 脚手架,含未跟踪的 `web/pkg/` wasm 产物)
- `Dockerfile.web`
- `nginx/`(仅含 web.conf)
- `.dockerignore`(仅服务于 web docker 构建)
- `tools/build-web-image`、`tools/rebuild-web`、`tools/run-web-image`

### 2. 代码去 Web 特判(不破坏桌面/移动)

- `lib/src/app/article_detail_view.dart:14` 的 `kIsWeb` 分支:
  webview 只支持 android/ios,web 与 **linux/windows 桌面** 都应走 fallback。
  移除 `kIsWeb` 判断后,桌面端仍需正确落到 fallback(靠 `defaultTargetPlatform`
  不等于 android/ios 自然成立)。保留 `flutter/foundation.dart` 若无其他用途则清理 import。
- **FRB 生成物保留不动**:`frb_generated.web.dart` 及 `frb_generated.dart` 的
  `if (dart.library.js_interop)` 条件导入是惰性的,仅在编译 web 时生效,不影响其他三端。
  强行删除需重跑 codegen 且改生成文件,风险高收益低,故保留。

### 3. 重写 GitHub Actions

`.github/workflows/release.yml`:

- 删除 `web-image` job 及 `release` job 对它的 `needs` 依赖与产物说明
- 新增 `windows` job:
  - `runs-on: windows-latest`
  - Rust toolchain + `flutter build windows --release`
  - 打包 Runner 输出目录为 zip(如 `ferrisfeed-<version>-windows-x64.zip`)
  - upload-artifact
- `release` job 的 `needs` 改为 `[prepare, android, linux, windows]`,下载 windows 产物,
  更新 release body(去掉 Web Docker 段,加 Windows 说明)

### 4. 清理冗余文件

- `dist/`(22MB 旧构建产物,文件名仍是旧的 `RSS_Reader-*` / `rss_reader-*`,未跟踪)
- `integration_test/`(空目录)

### 5. 文档更新

- `README.md`:删除 Web 运行/构建/Docker/限制 等章节(约 87-264 行相关段落),
  平台清单改为 Android / Linux / Windows
- 检查 `README.en.md` 是否有对应 Web 段落一并处理

## 明确不做

- 不删 `doc/`(含 MrRSS/oksskolten 参考项目与 CORS 分析文档,用户决定保留)
- 不删 `ios/`、`macos/` 脚手架
- 不动 Rust 侧 `reader.rs`、`ReaderController`、`ReaderRepository` 的核心业务逻辑
- 不重跑 FRB codegen 去清理 web 生成分支
- 不新建 `windows/` 脚手架(已存在)

## 验证清单

- `flutter analyze` 无新增错误(去掉 kIsWeb / import 后)
- `flutter test` 通过
- `cargo test`(rust/)通过
- `flutter build linux --release` 本地可构建(确认去 web 改动没波及桌面)
- Windows 构建仅在 CI 验证(本机为 Linux,无法本地跑 windows build)
- `grep -rniE "kIsWeb|Dockerfile.web|web-image|rebuild-web" .` 在非 doc/、非 FRB 生成文件中无残留
- release.yml 的 job 依赖图自洽(release needs 里无已删除的 web-image)
