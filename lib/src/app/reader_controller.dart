import 'package:flutter/material.dart';
import 'package:rss_reader/src/app/reader_repository.dart';
import 'package:rss_reader/src/rust/api/reader.dart';

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

  ReaderSnapshot get snapshot => _snapshot;
  List<Feed> get feeds => _snapshot.feeds;
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
      _isLoaded = true;
    } finally {
      _setWorking(false);
    }
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

  Future<void> addFeed(String feedUrl) async {
    _setWorking(true);
    try {
      final result = await _repository.importFeed(
        snapshotJson: _snapshotJson,
        feedUrl: feedUrl,
      );
      _selectedFeedId = result.feed.id;
      _showStarredOnly = false;
      _showUnreadOnly = false;
      _selectedArticleId = result.insertedArticles.isNotEmpty
          ? result.insertedArticles.first.id
          : null;
      await _replaceSnapshot(result.snapshotJson);
    } finally {
      _setWorking(false);
    }
  }

  Future<RefreshSummary> refreshFeeds() async {
    if (feeds.isEmpty) {
      throw const ReaderAppException('Add a feed before refreshing.');
    }

    _setWorking(true);
    var workingSnapshotJson = _snapshotJson;
    var refreshedFeeds = 0;
    var insertedArticles = 0;
    var failedFeeds = 0;

    try {
      final targetFeeds = _selectedFeedId == null
          ? List<Feed>.from(feeds)
          : feeds.where((feed) => feed.id == _selectedFeedId).toList();

      for (final feed in targetFeeds) {
        try {
          final result = await _repository.importFeed(
            snapshotJson: workingSnapshotJson,
            feedUrl: feed.sourceUrl,
          );
          workingSnapshotJson = result.snapshotJson;
          refreshedFeeds += 1;
          insertedArticles += result.insertedArticles.length;
          await _repository.saveSnapshotJson(workingSnapshotJson);
        } catch (error) {
          failedFeeds += 1;
          final errorMessage = error is ReaderAppException
              ? error.message
              : error.toString();
          workingSnapshotJson = recordFeedError(
            snapshotJson: workingSnapshotJson,
            feedId: feed.id,
            errorMessage: errorMessage,
          );
          await _repository.saveSnapshotJson(workingSnapshotJson);
        }
      }

      _snapshotJson = workingSnapshotJson;
      _syncFromSnapshotJson();
      notifyListeners();

      return RefreshSummary(
        refreshedFeeds: refreshedFeeds,
        insertedArticles: insertedArticles,
        failedFeeds: failedFeeds,
      );
    } finally {
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
      final nextSnapshotJson = removeFeed(
        snapshotJson: _snapshotJson,
        feedId: feedId,
      );
      _selectedFeedId = null;
      _showStarredOnly = false;
      _showUnreadOnly = false;
      _selectedArticleId = null;
      await _replaceSnapshot(nextSnapshotJson);
    } finally {
      _setWorking(false);
    }
  }

  Future<void> updateFeedViewMode(String feedId, ArticleViewMode mode) async {
    _setWorking(true);
    try {
      final nextSnapshotJson = setFeedViewMode(
        snapshotJson: _snapshotJson,
        feedId: feedId,
        viewMode: mode,
      );
      await _replaceSnapshot(nextSnapshotJson);
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
