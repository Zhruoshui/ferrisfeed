import 'package:flutter/foundation.dart';
import 'package:rss_reader/src/app/reader_repository.dart';
import 'package:rss_reader/src/rust/api/reader.dart';

class RefreshSummary {
  const RefreshSummary({
    required this.refreshedFeeds,
    required this.insertedArticles,
  });

  final int refreshedFeeds;
  final int insertedArticles;
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
  bool _isWorking = false;
  bool _isLoaded = false;

  ReaderSnapshot get snapshot => _snapshot;
  List<Feed> get feeds => _snapshot.feeds;
  List<ArticleListItem> get articles => _articles;
  Article? get selectedArticle => _selectedArticle;
  bool get isWorking => _isWorking;
  bool get isLoaded => _isLoaded;
  bool get hasFeeds => feeds.isNotEmpty;
  bool get hasArticles => articles.isNotEmpty;
  bool get isShowingStarredOnly => _showStarredOnly;
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
      _snapshotJson = await _repository.loadSnapshotJson();
      _syncFromSnapshotJson();
      _isLoaded = true;
    } finally {
      _setWorking(false);
    }
  }

  void showAllArticles() {
    _selectedFeedId = null;
    _showStarredOnly = false;
    _syncFromSnapshotJson();
    notifyListeners();
  }

  void showStarredArticles() {
    _selectedFeedId = null;
    _showStarredOnly = true;
    _syncFromSnapshotJson();
    notifyListeners();
  }

  void showFeed(String feedId) {
    _selectedFeedId = feedId;
    _showStarredOnly = false;
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

    try {
      final targetFeeds = _selectedFeedId == null
          ? List<Feed>.from(feeds)
          : feeds.where((feed) => feed.id == _selectedFeedId).toList();

      for (final feed in targetFeeds) {
        final result = await _repository.importFeed(
          snapshotJson: workingSnapshotJson,
          feedUrl: feed.sourceUrl,
        );
        workingSnapshotJson = result.snapshotJson;
        refreshedFeeds += 1;
        insertedArticles += result.insertedArticles.length;
        await _repository.saveSnapshotJson(workingSnapshotJson);
      }

      _snapshotJson = workingSnapshotJson;
      _syncFromSnapshotJson();
      notifyListeners();

      return RefreshSummary(
        refreshedFeeds: refreshedFeeds,
        insertedArticles: insertedArticles,
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
      _selectedArticleId = null;
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
