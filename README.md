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

### Web

本地调试：

```bash
flutter run -d web-server
```

Chrome 调试：

```bash
flutter run -d chrome \
  --web-header=Cross-Origin-Opener-Policy=same-origin \
  --web-header=Cross-Origin-Embedder-Policy=require-corp
```

生产构建：

```bash
flutter build web
```

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
