# 阅读体验四项改造：刷新容错 / 未读筛选 / 上下篇 / rendered 增强

## Goal

对照两个参考 RSS 项目（`doc/ref/MrRSS/analysis.md`、`doc/ref/obsskolren/analysis.md`）的分析结论，落地其中"P0/P1 小改动、高回报"的四项阅读体验改造，让当前 FerrisFeed 在不引入 SQLite/全文抓取/AI 等大改的前提下，先把"刷新可靠性、筛选完整度、详情页导航、桌面端渲染质量"补齐。这是后续数据库化与 AI 化之前的体验地基。

## What I already know

当前代码现状（已读 `reader_controller.dart` / `reader_repository.dart` / `article_detail_view.dart` / `reader_app.dart` / `rust/src/api/reader.rs` + 测试 + frb 0.16 API）：

- 持久化：整份 snapshot JSON 存 `shared_preferences` key `reader_snapshot_v1`，每次状态变更全量重编码+回写。Rust 拥有全部领域模型与状态流转（`import_feed_from_xml_sync` / `mark_article_read` / `toggle_article_star` / `remove_feed` / `set_feed_view_mode` / `clear_all_read_articles`）。
- `Feed` 字段：`id/title/source_url/site_url/description/unread_count/article_count/last_synced_at/article_view_mode`。**无** category、last_error、error_count、etag、refresh_interval。
- `Article` 字段：`id/feed_id/title/url/author/summary/content/published_at/is_read/is_starred`。
- 筛选：All / Starred / 单 feed。`_showStarredOnly` 存在，**无** `_showUnreadOnly`。
- `refreshFeeds()`：串行 for 循环，无 per-feed try/catch——`importFeed` 在 HTTP 非 2xx 或空响应时抛 `ReaderAppException`，中断整个循环，后续 feed 不刷新，错误冒泡成一次性 snackbar。
- 详情页：rendered / webpage / external 三模式。rendered 取 `content` 再 fallback `summary`。无全文抓取、图片放大、页内查找、上/下一篇。
- 桌面端（Linux/Windows）webview 不可用，走 `_RenderedArticleView`——rendered 质量 = 桌面端体验天花板。
- `ReaderApp` 只有 `Brightness.light`，**无 darkTheme**。
- `appDefaultViewMode` 仅存内存，重启即丢。
- 工具链：`flutter_rust_bridge_codegen` 2.12.0 可用；`lib/src/rust/api/reader.dart` 自动生成。FVM 锁定 Flutter 3.44.1。
- `flutter_widget_from_html` 0.16.1 `HtmlWidget` 支持 `onTapImage` / `customStylesBuilder` / `customWidgetBuilder`。

## Requirements

### 第 1 项：`refreshFeeds` 容错 + per-feed 错误持久化
- `Feed` 加 `last_error: Option<String>` 与 `error_count: i32`（`#[serde(default)]`，兼容旧 snapshot）。
- 成功 import 时清零（existing-feed 分支清 `last_error=None, error_count=0`；new-feed 分支初始化为 None/0；`add_feed` 同样初始化）。
- 新增 Rust `record_feed_error(snapshot_json, feed_id, error_message) -> Result<String, ReaderError>`：置 `last_error`、`error_count += 1`、`last_synced_at = now`。
- `refreshFeeds()` 循环内 try/catch 每个 feed：成功 → 累加 inserted；失败 → 调 `recordFeedError` 并保存、`failedFeeds++`、**继续下一个**。`refreshedFeeds` 改为成功数。
- `RefreshSummary` 加 `failedFeeds`。
- 侧栏 feed 项在 `lastError != null` 时显示红色错误提示（让持久化的错误状态可见）。
- 刷新结果 snackbar 在 `failedFeeds > 0` 时显示失败数。

### 第 2 项："只看未读"筛选
- `list_articles` 加参数 `show_unread_only: bool`，加 `.filter(|a| !show_unread_only || !a.is_read)`。
- Controller 加 `_showUnreadOnly` + `isShowingUnreadOnly` + `showUnreadArticles()`；`showAll/showStarred/showFeed` 互斥清零；`_syncFromSnapshotJson` 传 `showUnreadOnly`；`currentViewTitle` 加 "Unread" 分支。
- 侧栏在 All 与 Starred 之间加 "Unread" 项，count = `totalUnreadCount`，`selected` 当 `selectedFeedId == null && isShowingUnreadOnly`。All/Starred/feed 的 `selected` 条件相应加 `!isShowingUnreadOnly`。

### 第 3 项：上一篇 / 下一篇（页内查找后置）
- Controller 加 `selectAdjacentArticle(int offset)`（按 `_articles` 索引移动并调 `openArticle`）+ `canSelectPrevious/NextArticle`。
- `_ArticleDetailHeader` 工具栏 Wrap 加 ↑/↓ `IconButton.filledTonal`，边界时禁用（`onPressed: null`）。
- 推入路由 AppBar 也加上/下一篇；该路由 body 当前未包 `AnimatedBuilder`，用 `AnimatedBuilder(animation: controller)` 包住 body（顺带修 star/read 切换图标不更新的既有问题）。
- **页内查找本轮不做**（`flutter_widget_from_html` 无原生支持，需额外方案）。

### 第 4 项：rendered 模式渲染增强 + light/dark 主题
- 行宽：`_RenderedArticleView` 内容用 `Center` + `ConstrainedBox(maxWidth: 720)` 包裹。
- 字号控制：`HtmlWidget.textStyle` 乘字号倍数；controller 加 `readingFontScale`（默认 1.0，0.8–1.6，步进 0.1）+ A⁻/A⁺/重置按钮；持久化。
- 代码块：`customStylesBuilder` 命中 `pre` → background/padding/border-radius/overflow-x/monospace（暗色下用主题暗底）。
- 图片：`customStylesBuilder` 命中 `img` → max-width:100%/border-radius；`onTapImage` → `showDialog` 内 `InteractiveViewer` + `Image.network(src)`，失败 fallback `openInSystemBrowser`。
- **light/dark 主题**：`ReaderApp` 加 `darkTheme` + `themeMode`（light/dark/system，默认 system）；`MaterialApp` 用 `AnimatedBuilder(animation: controller)` 包裹以响应主题切换。controller 加 `themeMode` getter/setter，持久化。菜单/工具栏加主题切换入口。
- **rendered HTML 跟随主题**：`customStylesBuilder` 对带内联 `style`（含 `background`/`color`）的元素，在暗色下覆盖为 `transparent`/`inherit`，剥除 feed 内联白底，使正文跟随主题色；`pre` 给主题化背景。正文文字色已通过 `textStyle: Theme.of(context).textTheme.bodyLarge` 跟随主题。

## Acceptance Criteria

- [x] 单个 feed 刷新失败时，其余 feed 仍被刷新；失败 feed 的 `last_error`/`error_count` 持久化并在侧栏可见；snackbar 报成功/新增/失败三项计数。
- [x] 成功刷新后 `last_error` 清空、`error_count` 归零。
- [x] 侧栏 "Unread" 项可切到只看未读；与 All/Starred/单 feed 互斥；计数正确。
- [x] 详情页可用 ↑/↓ 在当前列表内移动并自动标记已读；首/末条禁用对应按钮；推入路由中同样可用且切换后视图刷新。
- [x] rendered 模式在宽屏下正文居中且不超过 ~720px；A⁻/A⁺ 可调字号并重启后保留；代码块有可读样式；图片可点击放大。
- [x] light/dark/system 主题可切换并持久化；切换后 UI 与 rendered 正文（含剥除内联白底）即时跟随；暗色下代码块/图片样式可读。
- [x] 旧 snapshot（无 `last_error`/`error_count`）加载不崩溃。
- [x] Rust 新增测试：`record_feed_error` 记录并累加、成功 import 后清零、`list_articles` unread 过滤。
- [x] 测试 mock 同步：`crateApiReaderListArticles` 加 `showUnreadOnly`、新增 `crateApiReaderRecordFeedError`、Feed JSON 加 `lastError`/`errorCount`。
- [x] `fvm flutter analyze` / `fvm flutter test` / `cargo test --manifest-path rust/Cargo.toml --offline` 全绿。

## Definition of Done

- Tests added/updated（Rust + Dart mock）。
- Lint / typecheck / cargo test green。
- 跨层 spec 同步更新（`frontend/state-management.md` 的 `listArticles` 签名、`backend/error-handling.md` 的 `record_feed_error`）。
- FRB 生成代码已重新生成并提交（`lib/src/rust/api/reader.dart`、`frb_generated.dart`）。

## Technical Approach

跨层契约变更（核心风险点，参考 `guides/cross-layer-thinking-guide.md`）：

- `Feed` 加字段 → Rust serde（`#[serde(default)]` 兼容旧数据）→ frb 重新生成 Dart `Feed`（`lastError: String?`、`errorCount: int`）→ 测试 mock 的 Feed JSON 加字段。**旧 snapshot 经 Rust `decode_snapshot` 解码时 serde default 填充，再经 frb 返回 Dart 时字段齐全，Dart 侧不会因缺字段崩溃**——这是兼容性的关键路径，需测试覆盖。
- `list_articles` 加参数 → Rust 签名 → frb 生成 `listArticles(showUnreadOnly: ...)` → controller 调用 → 测试 mock 签名同步。
- 新增 `record_feed_error` → frb 生成 `recordFeedError` → `_MockRustApi implements RustLibApi` 必须补实现，否则编译失败。

实现顺序：Rust 改 → `flutter_rust_bridge_codegen generate` → Dart controller/repo → `article_detail_view` → `reader_app` UI → 测试 mock → 验证。

字号持久化：`ReaderRepository` 已封装 `shared_preferences`，加 `getSetting(String)/setSetting(String,String)`；controller 在 `load()` 读 `reading_font_scale`（顺带持久化现在重启即丢的 `appDefaultViewMode`）。

## Decision (ADR-lite)

**Context**: 第 4 项"暗色模式下的 HTML 重写"依赖一个尚不存在的暗色主题（`ReaderApp` 只有 `Brightness.light`、无 `darkTheme`）。
**Decision**: 本轮顺带加 light/dark/system 主题切换，并让 rendered HTML 跟随主题（剥除 feed 内联白底）。
**Consequences**: 范围较"延后暗色"扩大约 1.5 倍，但一步到位，避免后续返工；需新增 `themeMode` 持久化与 `MaterialApp` 响应式重建；`customStylesBuilder` 需按主题模式分支处理内联色。HTML 文字色已通过 `textStyle` 跟随主题，衔接平滑。

## Open Questions

- （已解决）第 4 项暗色模式范围：用户选择"本轮顺带加 light/dark 切换"。

## Out of Scope

- SQLite 化存储、OPML、分类、ETag/Last-Modified、全文抓取、AI 摘要/翻译、FTS 搜索（属后续任务）。
- 页内查找（`flutter_widget_from_html` 无原生支持）。
- 主题相关的进阶项（自定义强调色、字号跟随系统、高对比度）——本轮只做 light/dark/system 三态。

## Technical Notes

- 参考分析：`doc/ref/MrRSS/analysis.md`、`doc/ref/obsskolren/analysis.md`（两份独立给出一致的 P0/P1 优先级）。
- 跨层契约 spec（需同步）：`.trellis/spec/frontend/state-management.md`（`listArticles` 签名）、`.trellis/spec/backend/error-handling.md`（FRB 错误契约 + `record_feed_error`）。
- 关键文件：`rust/src/api/reader.rs`（Feed/list_articles/record_feed_error/import 清错）、`lib/src/app/reader_controller.dart`、`lib/src/app/reader_repository.dart`、`lib/src/app/article_detail_view.dart`、`lib/src/app/reader_app.dart`、`test/reader_import_test.dart`。
- frb 0.16 `HtmlWidget` API 已确认：`onTapImage = void Function(ImageMetadata)?`、`customStylesBuilder = StylesMap? Function(dom.Element)`、`customWidgetBuilder = Widget? Function(dom.Element)`。
- 验证命令：`flutter_rust_bridge_codegen generate` / `fvm flutter analyze` / `fvm flutter test` / `cargo test --manifest-path rust/Cargo.toml --offline`。
