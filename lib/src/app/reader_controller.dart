import 'package:flutter/material.dart';
import 'package:rss_reader/src/app/reader_repository.dart';
import 'package:rss_reader/src/rust/api/entry.dart' as rust_entry;
import 'package:rss_reader/src/rust/api/feed.dart' as rust_feed;
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

/// Page size for the entry list. Additional pages are appended on
/// scroll-to-bottom (see [loadMore]).
const _entryPageSize = 50;

/// Controller for the reading UI, backed by the persisted SQLite entry/feed
/// APIs (P2a). The in-memory JSON snapshot is gone: every list/detail/read/
/// star mutation round-trips through the FRB entry API so state survives
/// restarts and stays consistent with the feed sidebar.
class ReaderController extends ChangeNotifier {
  ReaderController({required ReaderRepository repository}) : this._(repository);

  ReaderController._(this._repository);

  final ReaderRepository _repository;

  List<Feed> _dbFeeds = const [];
  List<EntryListItem> _articles = const [];
  Entry? _selectedEntry;
  String? _selectedEntryId;
  /// Previous (newer) / next (older) entry ids for the selected entry, within
  /// the current filter context. Refreshed whenever an entry is opened.
  AdjacentEntries? _adjacent;
  String? _selectedFeedId;
  bool _showStarredOnly = false;
  bool _showUnreadOnly = false;
  bool _isWorking = false;
  bool _isLoaded = false;
  bool _isLoadingMore = false;
  bool _hasMore = false;

  /// Current feed-sync progress (`null` when not syncing). Updated from the
  /// `StreamSink<SyncProgress>` events emitted by `refreshAllFeeds` so the UI
  /// can show per-feed progress (total/completed/new) during a refresh.
  SyncProgress? _syncProgress;

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

  /// Effective view mode for the currently selected entry, or `null` when no
  /// entry is selected.
  ArticleViewMode? get selectedArticleEffectiveMode {
    final entry = _selectedEntry;
    if (entry == null) {
      return null;
    }
    return effectiveViewModeForFeed(entry.feedId);
  }

  /// Current sync progress, or `null` when no refresh is running.
  SyncProgress? get syncProgress => _syncProgress;

  List<Feed> get feeds => _dbFeeds;
  List<EntryListItem> get articles => _articles;
  Entry? get selectedArticle => _selectedEntry;
  bool get isWorking => _isWorking;
  bool get isLoaded => _isLoaded;
  bool get hasFeeds => feeds.isNotEmpty;
  bool get hasArticles => articles.isNotEmpty;
  bool get isShowingStarredOnly => _showStarredOnly;
  bool get isShowingUnreadOnly => _showUnreadOnly;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  String? get selectedFeedId => _selectedFeedId;
  Feed? get selectedFeed => _findFeed(_selectedFeedId);
  int get totalUnreadCount =>
      feeds.fold(0, (sum, feed) => sum + feed.unreadCount);
  /// Count of starred entries among the currently loaded article list.
  int get starredCount =>
      _articles.where((article) => article.isStarred).length;
  int get visibleUnreadCount =>
      _articles.where((article) => !article.isRead).length;
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
      await _loadDbFeeds();
      await _reloadArticles();
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
      // Settings are best-effort.
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

  /// The filter arguments passed to `listEntries` / `getAdjacentEntries` for
  /// the current view.
  bool get _filterUnreadOnly => _showUnreadOnly;
  bool get _filterStarredOnly => _showStarredOnly;

  Future<void> showAllArticles() async {
    _selectedFeedId = null;
    _showStarredOnly = false;
    _showUnreadOnly = false;
    _selectedEntryId = null;
    _selectedEntry = null;
    _adjacent = null;
    await _runAndNotify(_reloadArticles);
  }

  Future<void> showStarredArticles() async {
    _selectedFeedId = null;
    _showStarredOnly = true;
    _showUnreadOnly = false;
    _selectedEntryId = null;
    _selectedEntry = null;
    _adjacent = null;
    await _runAndNotify(_reloadArticles);
  }

  Future<void> showUnreadArticles() async {
    _selectedFeedId = null;
    _showStarredOnly = false;
    _showUnreadOnly = true;
    _selectedEntryId = null;
    _selectedEntry = null;
    _adjacent = null;
    await _runAndNotify(_reloadArticles);
  }

  Future<void> showFeed(String feedId) async {
    _selectedFeedId = feedId;
    _showStarredOnly = false;
    _showUnreadOnly = false;
    _selectedEntryId = null;
    _selectedEntry = null;
    _adjacent = null;
    await _runAndNotify(_reloadArticles);
  }

  /// Discovers feed candidates at [url] via the Rust HTTP + parse/discover
  /// pipeline.
  Future<List<FeedCandidate>> discoverFeeds(String url) async {
    _setWorking(true);
    try {
      return await rust_feed.discoverFeeds(url: url);
    } finally {
      _setWorking(false);
    }
  }

  /// Subscribes to [url] via Rust (fetch + parse + normalize + persist). Reloads
  /// the DB feed list and selects the new feed.
  Future<void> subscribeFeed(String url) async {
    _setWorking(true);
    try {
      final feed = await rust_feed.subscribeFeed(url: url);
      await _loadDbFeeds();
      _selectedFeedId = feed.id;
      _showStarredOnly = false;
      _showUnreadOnly = false;
      _selectedEntryId = null;
      _selectedEntry = null;
      _adjacent = null;
      await _reloadArticles();
      notifyListeners();
    } finally {
      _setWorking(false);
    }
  }

  Future<RefreshSummary> refreshFeeds() async {
    if (feeds.isEmpty) {
      throw const ReaderAppException('Add a feed before refreshing.');
    }

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
      // Reload feeds (unread/article counts) and the entry list so newly
      // synced entries appear.
      await _loadDbFeeds();
      await _reloadArticles();
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
      _selectedEntryId = null;
      _selectedEntry = null;
      _adjacent = null;
      await _loadDbFeeds();
      await _reloadArticles();
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

  /// Opens (and selects) [entryId]. Marks the entry read on open and refreshes
  /// the prev/next neighbours within the current filter.
  Future<void> openArticle(String entryId, {bool markAsRead = true}) async {
    _setWorking(true);
    try {
      var entry = await rust_entry.getEntry(entryId: entryId);
      if (markAsRead && !entry.isRead) {
        await rust_entry.markEntryRead(entryId: entryId, isRead: true);
        entry = await rust_entry.getEntry(entryId: entryId);
        // Reflect the read state in the cached list item and the feed counts.
        _updateArticleInList(entryId, isRead: true);
        await _loadDbFeeds();
      }
      _selectedEntryId = entryId;
      _selectedEntry = entry;
      _adjacent = await rust_entry.getAdjacentEntries(
        entryId: entryId,
        feedId: _selectedFeedId,
        unreadOnly: _filterUnreadOnly,
        starredOnly: _filterStarredOnly,
      );
      notifyListeners();
    } finally {
      _setWorking(false);
    }
  }

  /// Sets the selected entry's read state.
  Future<void> setSelectedArticleRead(bool isRead) async {
    final entry = _selectedEntry;
    if (entry == null || entry.isRead == isRead) {
      return;
    }

    _setWorking(true);
    try {
      await rust_entry.markEntryRead(entryId: entry.id, isRead: isRead);
      _selectedEntry = _withEntryUpdates(entry, isRead: isRead);
      _updateArticleInList(entry.id, isRead: isRead);
      await _loadDbFeeds();
      notifyListeners();
    } finally {
      _setWorking(false);
    }
  }

  /// Toggles the selected entry's star. The new starred state is returned by
  /// the API and applied locally.
  Future<void> toggleSelectedArticleStar() async {
    final entry = _selectedEntry;
    if (entry == null) {
      return;
    }

    _setWorking(true);
    try {
      final nowStarred =
          await rust_entry.toggleEntryStar(entryId: entry.id);
      _selectedEntry = _withEntryUpdates(entry, isStarred: nowStarred);
      _updateArticleInList(entry.id, isStarred: nowStarred);
      notifyListeners();
    } finally {
      _setWorking(false);
    }
  }

  /// Moves to the previous (offset -1, newer) or next (offset +1, older)
  /// entry within the current filter, using the cached adjacent ids.
  Future<void> selectAdjacentArticle(int offset) async {
    final targetId = offset < 0 ? _adjacent?.prev : _adjacent?.next;
    if (targetId == null) {
      return;
    }
    await openArticle(targetId);
  }

  bool get canSelectPreviousArticle => _adjacent?.prev != null;
  bool get canSelectNextArticle => _adjacent?.next != null;

  /// Appends the next page of entries to the article list (scroll-to-bottom
  /// pagination). No-op when there are no more entries or a page is loading.
  Future<void> loadMore() async {
    if (!_hasMore || _isLoadingMore) {
      return;
    }
    _isLoadingMore = true;
    notifyListeners();
    try {
      final next = await rust_entry.listEntries(
        feedId: _selectedFeedId,
        unreadOnly: _filterUnreadOnly,
        starredOnly: _filterStarredOnly,
        limit: _entryPageSize,
        offset: _articles.length,
      );
      _articles = [..._articles, ...next];
      _hasMore = next.length >= _entryPageSize;
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  String feedTitleFor(String feedId) {
    return _findFeed(feedId)?.title ?? 'Unknown feed';
  }

  @override
  void dispose() {
    _repository.dispose();
    super.dispose();
  }

  // --- internals ------------------------------------------------------------

  Future<void> _reloadArticles() async {
    final items = await rust_entry.listEntries(
      feedId: _selectedFeedId,
      unreadOnly: _filterUnreadOnly,
      starredOnly: _filterStarredOnly,
      limit: _entryPageSize,
      offset: 0,
    );
    _articles = items;
    _hasMore = items.length >= _entryPageSize;

    // Keep the current selection if it is still in the list; otherwise clear
    // the detail pane.
    final selectedStillVisible = _selectedEntryId != null &&
        items.any((item) => item.id == _selectedEntryId);
    if (!selectedStillVisible) {
      _selectedEntryId = null;
      _selectedEntry = null;
      _adjacent = null;
    }
  }

  Future<void> _runAndNotify(Future<void> Function() action) async {
    _setWorking(true);
    try {
      await action();
      notifyListeners();
    } finally {
      _setWorking(false);
    }
  }

  /// Reconstructs an [EntryListItem] with the given fields overridden, so the
  /// cached list reflects mutations without a full reload (keeps the list
  /// stable while reading).
  void _updateArticleInList(String id, {bool? isRead, bool? isStarred}) {
    final index = _articles.indexWhere((item) => item.id == id);
    if (index < 0) {
      return;
    }
    final old = _articles[index];
    _articles[index] = EntryListItem(
      id: old.id,
      feedId: old.feedId,
      feedTitle: old.feedTitle,
      title: old.title,
      summary: old.summary,
      publishedAt: old.publishedAt,
      isRead: isRead ?? old.isRead,
      isStarred: isStarred ?? old.isStarred,
    );
  }

  Entry _withEntryUpdates(Entry entry, {bool? isRead, bool? isStarred}) {
    return Entry(
      id: entry.id,
      feedId: entry.feedId,
      title: entry.title,
      url: entry.url,
      content: entry.content,
      summary: entry.summary,
      author: entry.author,
      imageUrl: entry.imageUrl,
      publishedAt: entry.publishedAt,
      isRead: isRead ?? entry.isRead,
      isStarred: isStarred ?? entry.isStarred,
      readProgress: entry.readProgress,
      createdAt: entry.createdAt,
    );
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

  void _setWorking(bool value) {
    _isWorking = value;
    notifyListeners();
  }
}
