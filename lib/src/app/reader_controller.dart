import 'package:flutter/material.dart';
import 'package:rss_reader/src/app/reader_repository.dart';
import 'package:rss_reader/src/rust/api/feed.dart' as rust_feed;
import 'package:rss_reader/src/rust/api/reader.dart';
import 'package:rss_reader/src/rust/api/types.dart';

class RefreshSummary {
  const RefreshSummary({
    required this.refreshedFeeds,
    required this.insertedArticles,
    required this.failedFeeds,
  });

  final int refreshedFeeds;
  final int insertedArticles;
  final int failedFeeds;
}

class ReaderController extends ChangeNotifier {
  ReaderController({required ReaderRepository repository}) : this._(repository);

  ReaderController._(this._repository);

  final ReaderRepository _repository;

  ReaderSnapshot _snapshot = const ReaderSnapshot(
    feeds: [],
    articles: [],
    lastUpdatedAt: null,
  );
  String _snapshotJson = '';
  List<ArticleListItem> _articles = const [];
  Article? _selectedArticle;
  String? _selectedArticleId;
  String? _selectedFeedId;
  bool _showStarredOnly = false;
  bool _showUnreadOnly = false;
  bool _isWorking = false;
  bool _isLoaded = false;

  /// Current feed-sync progress (`null` when not syncing). Updated from the
  /// `StreamSink<SyncProgress>` events emitted by `refreshAllFeeds` so the UI
  /// can show per-feed progress (total/completed/new) during a refresh.
  SyncProgress? _syncProgress;

  /// Feeds shown in the sidebar — DB-backed via `listFeeds()` (P1a). Article
  /// reading still uses the in-memory snapshot until P2a, so a newly subscribed
  /// feed's ID will not match any snapshot articles (no entries are synced
  /// until P1b). P1b+P2a reconcile the two sources.
  List<Feed> _dbFeeds = const [];

  /// App-wide default mode used when a feed is configured as
  /// [ArticleViewMode.global]. `rendered` keeps content in-app by default.
  ArticleViewMode _appDefaultViewMode = ArticleViewMode.rendered;

  /// Reader font scale multiplier for rendered articles. Persisted so the
  /// user's preference survives restarts. Clamped to 0.8–1.6 in 0.1 steps.
  double _readingFontScale = 1.0;

  /// Light/dark/system theme mode. Persisted across restarts.
  ThemeMode _themeMode = ThemeMode.system;

  ArticleViewMode get appDefaultViewMode => _appDefaultViewMode;

  set appDefaultViewMode(ArticleViewMode mode) {
    final resolved = mode == ArticleViewMode.global
        ? ArticleViewMode.rendered
        : mode;
    if (resolved == _appDefaultViewMode) {
      return;
    }
    _appDefaultViewMode = resolved;
    _persistSetting('app_default_view_mode', resolved.name);
    notifyListeners();
  }

  /// Current reading font scale for rendered articles.
  double get readingFontScale => _readingFontScale;

  /// Sets the reading font scale, clamped to 0.8–1.6. Persists the value.
  set readingFontScale(double value) {
    final clamped = (value * 10).round() / 10;
    final bounded = clamped.clamp(0.8, 1.6);
    if ((bounded - _readingFontScale).abs() < 0.01) {
      return;
    }
    _readingFontScale = bounded;
    _persistSetting('reading_font_scale', bounded.toStringAsFixed(1));
    notifyListeners();
  }

  /// Current light/dark/system theme mode.
  ThemeMode get themeMode => _themeMode;

  /// Sets the theme mode and persists it.
  set themeMode(ThemeMode mode) {
    if (mode == _themeMode) {
      return;
    }
    _themeMode = mode;
    _persistSetting('theme_mode', mode.name);
    notifyListeners();
  }

  /// Resolves the effective view mode for [feedId], collapsing `global` to the
  /// current app default. Never returns [ArticleViewMode.global].
  ArticleViewMode effectiveViewModeForFeed(String feedId) {
    final feed = _findFeed(feedId);
    final feedMode = feed?.articleViewMode ?? ArticleViewMode.global;
    if (feedMode == ArticleViewMode.global) {
      return _appDefaultViewMode;
    }
    return feedMode;
  }

  /// Effective view mode for the currently selected article, or `null` when no
  /// article is selected.
  ArticleViewMode? get selectedArticleEffectiveMode {
    final article = _selectedArticle;
    if (article == null) {
      return null;
    }
    return effectiveViewModeForFeed(article.feedId);
  }

  /// Current sync progress, or `null` when no refresh is running. The UI binds
  /// to this to render a progress bar + per-feed status.
  SyncProgress? get syncProgress => _syncProgress;

  ReaderSnapshot get snapshot => _snapshot;
  List<Feed> get feeds => _dbFeeds;
  List<ArticleListItem> get articles => _articles;
  Article? get selectedArticle => _selectedArticle;
  bool get isWorking => _isWorking;
  bool get isLoaded => _isLoaded;
  bool get hasFeeds => feeds.isNotEmpty;
  bool get hasArticles => articles.isNotEmpty;
  bool get isShowingStarredOnly => _showStarredOnly;
  bool get isShowingUnreadOnly => _showUnreadOnly;
  String? get selectedFeedId => _selectedFeedId;
  Feed? get selectedFeed => _findFeed(_selectedFeedId);
  int get totalUnreadCount =>
      feeds.fold(0, (sum, feed) => sum + feed.unreadCount);
  int get starredCount =>
      _snapshot.articles.where((article) => article.isStarred).length;
  int get visibleUnreadCount =>
      _articles.where((article) => !article.isRead).length;
  bool get hasReadArticles =>
      _snapshot.articles.any((article) => article.isRead);
  bool get canRemoveSelectedFeed => _selectedFeedId != null;

  String get currentViewTitle {
    if (_showStarredOnly) {
      return 'Starred';
    }
    if (_showUnreadOnly) {
      return 'Unread';
    }
    if (selectedFeed != null) {
      return selectedFeed!.title;
    }
    return 'All articles';
  }

  String get currentViewSubtitle {
    if (!_isLoaded) {
      return 'Loading';
    }
    if (!hasFeeds) {
      return 'No feeds yet';
    }
    final unread = visibleUnreadCount;
    final articleCount = _articles.length;
    return '$articleCount articles, $unread unread';
  }

  Future<void> load() async {
    _setWorking(true);
    try {
      await _loadPersistedSettings();
      _snapshotJson = await _repository.loadSnapshotJson();
      _syncFromSnapshotJson();
      await _loadDbFeeds();
      _isLoaded = true;
    } finally {
      _setWorking(false);
    }
  }

  Future<void> _loadDbFeeds() async {
    _dbFeeds = await rust_feed.listFeeds();
  }

  Future<void> _loadPersistedSettings() async {
    final fontScaleStr = await _repository.getSetting('reading_font_scale');
    if (fontScaleStr != null) {
      final parsed = double.tryParse(fontScaleStr);
      if (parsed != null) {
        _readingFontScale = parsed.clamp(0.8, 1.6);
      }
    }
    final themeModeStr = await _repository.getSetting('theme_mode');
    if (themeModeStr != null) {
      _themeMode = _parseThemeMode(themeModeStr) ?? _themeMode;
    }
    final defaultViewStr = await _repository.getSetting('app_default_view_mode');
    if (defaultViewStr != null) {
      _appDefaultViewMode = _parseViewModeName(defaultViewStr) ?? _appDefaultViewMode;
    }
  }

  Future<void> _persistSetting(String key, String value) async {
    try {
      await _repository.setSetting(key, value);
    } catch (_) {
      // Settings are best-effort; snapshot persistence is the durable path.
    }
  }

  static ThemeMode? _parseThemeMode(String name) {
    switch (name) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return null;
    }
  }

  static ArticleViewMode? _parseViewModeName(String name) {
    switch (name) {
      case 'rendered':
        return ArticleViewMode.rendered;
      case 'webpage':
        return ArticleViewMode.webpage;
      case 'external':
      case 'external_':
        return ArticleViewMode.external_;
      case 'global':
        return ArticleViewMode.global;
      default:
        return null;
    }
  }

  void showAllArticles() {
    _selectedFeedId = null;
    _showStarredOnly = false;
    _showUnreadOnly = false;
    _syncFromSnapshotJson();
    notifyListeners();
  }

  void showStarredArticles() {
    _selectedFeedId = null;
    _showStarredOnly = true;
    _showUnreadOnly = false;
    _syncFromSnapshotJson();
    notifyListeners();
  }

  void showUnreadArticles() {
    _selectedFeedId = null;
    _showStarredOnly = false;
    _showUnreadOnly = true;
    _syncFromSnapshotJson();
    notifyListeners();
  }

  void showFeed(String feedId) {
    _selectedFeedId = feedId;
    _showStarredOnly = false;
    _showUnreadOnly = false;
    _syncFromSnapshotJson();
    notifyListeners();
  }

  /// Discovers feed candidates at [url] via the Rust HTTP + parse/discover
  /// pipeline. The add-feed dialog calls this, shows a picker when there are
  /// multiple candidates, then calls [subscribeFeed].
  Future<List<FeedCandidate>> discoverFeeds(String url) async {
    _setWorking(true);
    try {
      return await rust_feed.discoverFeeds(url: url);
    } finally {
      _setWorking(false);
    }
  }

  /// Subscribes to [url] via Rust (fetch + parse + normalize + persist). Reloads
  /// the DB feed list and selects the new feed. Persists feed metadata only —
  /// entry sync is P1b.
  Future<void> subscribeFeed(String url) async {
    _setWorking(true);
    try {
      final feed = await rust_feed.subscribeFeed(url: url);
      await _loadDbFeeds();
      _selectedFeedId = feed.id;
      _showStarredOnly = false;
      _showUnreadOnly = false;
      _selectedArticleId = null;
      _syncFromSnapshotJson();
      notifyListeners();
    } finally {
      _setWorking(false);
    }
  }

  Future<RefreshSummary> refreshFeeds() async {
    if (feeds.isEmpty) {
      throw const ReaderAppException('Add a feed before refreshing.');
    }

    // P1b: real feed sync. `refreshAllFeeds` returns a `Stream<SyncProgress>`
    // (one event per feed + a final summary event with `done = true`). The
    // stream is consumed with `await for`; per-feed progress updates the UI via
    // `notifyListeners`. Per-feed failures are isolated in Rust (recorded on the
    // feed row + reported in the event's `error` field), so the stream always
    // completes — only a catastrophic setup error (e.g. DB not initialized)
    // throws, which `_runGuardedResult` surfaces.
    _setWorking(true);
    var completed = 0;
    var failed = 0;
    var totalNew = 0;
    try {
      final stream = rust_feed.refreshAllFeeds();
      await for (final progress in stream) {
        completed = progress.completed;
        failed = progress.failed;
        totalNew = progress.totalNewEntries;
        _syncProgress = progress;
        notifyListeners();
      }
      // Reload the DB feed list so unread/article counts reflect the new entries.
      await _loadDbFeeds();
      _syncFromSnapshotJson();
      notifyListeners();
      return RefreshSummary(
        refreshedFeeds: completed,
        insertedArticles: totalNew,
        failedFeeds: failed,
      );
    } finally {
      _syncProgress = null;
      _setWorking(false);
    }
  }

  Future<void> removeSelectedFeed() async {
    final feedId = _selectedFeedId;
    if (feedId == null) {
      return;
    }

    _setWorking(true);
    try {
      await rust_feed.deleteFeed(feedId: feedId);
      _selectedFeedId = null;
      _showStarredOnly = false;
      _showUnreadOnly = false;
      _selectedArticleId = null;
      await _loadDbFeeds();
      _syncFromSnapshotJson();
      notifyListeners();
    } finally {
      _setWorking(false);
    }
  }

  Future<void> updateFeedViewMode(String feedId, ArticleViewMode mode) async {
    _setWorking(true);
    try {
      await rust_feed.setFeedViewMode(feedId: feedId, viewMode: mode);
      await _loadDbFeeds();
      notifyListeners();
    } finally {
      _setWorking(false);
    }
  }

  Future<void> clearReadArticles() async {
    _setWorking(true);
    try {
      final nextSnapshotJson = clearAllReadArticles(
        snapshotJson: _snapshotJson,
      );
      if (_selectedArticle != null && _selectedArticle!.isRead) {
        _selectedArticleId = null;
      }
      await _replaceSnapshot(nextSnapshotJson);
    } finally {
      _setWorking(false);
    }
  }

  Future<void> openArticle(String articleId, {bool markAsRead = true}) async {
    final existing = getArticle(
      snapshotJson: _snapshotJson,
      articleId: articleId,
    );

    if (markAsRead && !existing.isRead) {
      _setWorking(true);
      try {
        final nextSnapshotJson = markArticleRead(
          snapshotJson: _snapshotJson,
          articleId: articleId,
          isRead: true,
        );
        _selectedArticleId = articleId;
        await _replaceSnapshot(nextSnapshotJson);
      } finally {
        _setWorking(false);
      }
      return;
    }

    _selectedArticleId = articleId;
    _selectedArticle = existing;
    notifyListeners();
  }

  Future<void> setSelectedArticleRead(bool isRead) async {
    final article = _selectedArticle;
    if (article == null || article.isRead == isRead) {
      return;
    }

    _setWorking(true);
    try {
      final nextSnapshotJson = markArticleRead(
        snapshotJson: _snapshotJson,
        articleId: article.id,
        isRead: isRead,
      );
      _selectedArticleId = article.id;
      await _replaceSnapshot(nextSnapshotJson);
    } finally {
      _setWorking(false);
    }
  }

  Future<void> toggleSelectedArticleStar() async {
    final article = _selectedArticle;
    if (article == null) {
      return;
    }

    _setWorking(true);
    try {
      final nextSnapshotJson = toggleArticleStar(
        snapshotJson: _snapshotJson,
        articleId: article.id,
      );
      _selectedArticleId = article.id;
      await _replaceSnapshot(nextSnapshotJson);
    } finally {
      _setWorking(false);
    }
  }

  /// Moves the selected article by [offset] positions within the current
  /// article list. Opens (and marks read) the target article. No-op when the
  /// resulting index is out of bounds.
  Future<void> selectAdjacentArticle(int offset) async {
    if (_articles.isEmpty || _selectedArticleId == null) {
      return;
    }
    final currentIndex = _articles.indexWhere(
      (article) => article.id == _selectedArticleId,
    );
    if (currentIndex < 0) {
      return;
    }
    final targetIndex = currentIndex + offset;
    if (targetIndex < 0 || targetIndex >= _articles.length) {
      return;
    }
    await openArticle(_articles[targetIndex].id);
  }

  bool get canSelectPreviousArticle {
    if (_articles.isEmpty || _selectedArticleId == null) {
      return false;
    }
    final currentIndex = _articles.indexWhere(
      (article) => article.id == _selectedArticleId,
    );
    return currentIndex > 0;
  }

  bool get canSelectNextArticle {
    if (_articles.isEmpty || _selectedArticleId == null) {
      return false;
    }
    final currentIndex = _articles.indexWhere(
      (article) => article.id == _selectedArticleId,
    );
    return currentIndex >= 0 && currentIndex < _articles.length - 1;
  }

  String feedTitleFor(String feedId) {
    return _findFeed(feedId)?.title ?? 'Unknown feed';
  }

  @override
  void dispose() {
    _repository.dispose();
    super.dispose();
  }

  Feed? _findFeed(String? feedId) {
    if (feedId == null) {
      return null;
    }
    for (final feed in feeds) {
      if (feed.id == feedId) {
        return feed;
      }
    }
    return null;
  }

  Future<void> _replaceSnapshot(String snapshotJson) async {
    _snapshotJson = snapshotJson;
    await _repository.saveSnapshotJson(snapshotJson);
    _syncFromSnapshotJson();
    notifyListeners();
  }

  void _syncFromSnapshotJson() {
    _snapshot = decodeReaderSnapshot(snapshotJson: _snapshotJson);
    _articles = listArticles(
      snapshotJson: _snapshotJson,
      feedId: _selectedFeedId,
      showStarredOnly: _showStarredOnly,
      showUnreadOnly: _showUnreadOnly,
    );

    if (_articles.isEmpty) {
      _selectedArticleId = null;
      _selectedArticle = null;
      return;
    }

    final selectedStillVisible =
        _selectedArticleId != null &&
        _articles.any((article) => article.id == _selectedArticleId);
    if (!selectedStillVisible) {
      _selectedArticleId = _articles.first.id;
    }

    _selectedArticle = getArticle(
      snapshotJson: _snapshotJson,
      articleId: _selectedArticleId!,
    );
  }

  void _setWorking(bool value) {
    _isWorking = value;
    notifyListeners();
  }
}
