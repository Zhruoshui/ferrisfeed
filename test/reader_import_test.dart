import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rss_reader/main.dart';
import 'package:rss_reader/src/app/article_detail_view.dart';
import 'package:rss_reader/src/app/reader_controller.dart';
import 'package:rss_reader/src/app/reader_repository.dart';
import 'package:rss_reader/src/rust/api/reader.dart';
import 'package:rss_reader/src/rust/api/types.dart';
import 'package:rss_reader/src/rust/frb_generated.dart';

void main() {
  // A single mock is installed once (FRB holds it as a static singleton); its
  // DB-backed feed state is reset before each test so tests are isolated.
  late _MockRustApi mockApi;

  setUpAll(() {
    mockApi = _MockRustApi();
    RustLib.initMock(api: mockApi);
  });

  setUp(() {
    mockApi.reset();
  });

  // --- Feed management (DB-backed, P1a) -------------------------------------

  test('subscribeFeed persists and selects the feed', () async {
    final controller = ReaderController(repository: ReaderRepository.memory());
    await controller.load();
    await controller.subscribeFeed('https://example.com/feed.xml');

    expect(controller.feeds.length, 1);
    expect(controller.feeds.first.sourceUrl, 'https://example.com/feed.xml');
    expect(controller.selectedFeedId, controller.feeds.first.id);
  });

  test('subscribeFeed is idempotent for the same URL', () async {
    final controller = ReaderController(repository: ReaderRepository.memory());
    await controller.load();
    await controller.subscribeFeed('https://example.com/feed.xml');
    await controller.subscribeFeed('https://example.com/feed.xml');

    expect(controller.feeds.length, 1);
  });

  test('discoverFeeds returns a candidate for a feed URL', () async {
    final controller = ReaderController(repository: ReaderRepository.memory());
    await controller.load();

    final candidates =
        await controller.discoverFeeds('https://example.com/feed.xml');
    expect(candidates.length, 1);
    expect(candidates.first.url, 'https://example.com/feed.xml');
  });

  test('removeSelectedFeed deletes the feed', () async {
    final controller = ReaderController(repository: ReaderRepository.memory());
    await controller.load();
    await controller.subscribeFeed('https://example.com/feed.xml');
    controller.showFeed(controller.feeds.first.id);

    await controller.removeSelectedFeed();

    expect(controller.feeds.isEmpty, isTrue);
    expect(controller.selectedFeedId, isNull);
  });

  test('feed view mode resolves global to app default and persists', () async {
    final controller = ReaderController(repository: ReaderRepository.memory());
    await controller.load();
    await controller.subscribeFeed('https://example.com/feed.xml');
    final feedId = controller.feeds.first.id;

    // Default: feed mode is global, app default is rendered.
    expect(controller.feeds.first.articleViewMode, ArticleViewMode.global);
    expect(
      controller.effectiveViewModeForFeed(feedId),
      ArticleViewMode.rendered,
    );

    // App default changes flow through global feeds.
    controller.appDefaultViewMode = ArticleViewMode.external_;
    expect(
      controller.effectiveViewModeForFeed(feedId),
      ArticleViewMode.external_,
    );

    // An explicit feed mode overrides the app default and persists.
    await controller.updateFeedViewMode(feedId, ArticleViewMode.webpage);
    expect(controller.feeds.first.articleViewMode, ArticleViewMode.webpage);
    expect(
      controller.effectiveViewModeForFeed(feedId),
      ArticleViewMode.webpage,
    );
  });

  test('refresh reloads the feed list', () async {
    final controller = ReaderController(repository: ReaderRepository.memory());
    await controller.load();
    await controller.subscribeFeed('https://example.com/feed.xml');

    final summary = await controller.refreshFeeds();
    expect(summary.refreshedFeeds, 1);
    expect(summary.failedFeeds, 0);
  });

  // --- Entry reading (snapshot-based, unchanged until P2a) ------------------
  //
  // These pre-populate the in-memory snapshot directly (the path the entry
  // reading UI still uses). The "All articles" view shows the snapshot articles
  // regardless of the DB-backed feed list.

  test('unread filter shows only unread articles', () async {
    final controller = ReaderController(
      repository: ReaderRepository.memory(
        initialSnapshotJson: _snapshotWithTwoArticles,
      ),
    );
    await controller.load();
    expect(controller.articles.length, 2);

    final firstArticleId = controller.articles.first.id;
    await controller.openArticle(firstArticleId);

    controller.showAllArticles();
    expect(controller.articles.length, 2);

    controller.showUnreadArticles();
    expect(controller.articles.length, 1);
    expect(controller.articles.first.isRead, isFalse);
  });

  test('adjacent article navigation moves within the list', () async {
    final controller = ReaderController(
      repository: ReaderRepository.memory(
        initialSnapshotJson: _snapshotWithTwoArticles,
      ),
    );
    await controller.load();
    expect(controller.articles.length, 2);

    // After load the newest article (index 0) is selected.
    expect(controller.canSelectPreviousArticle, isFalse);
    expect(controller.canSelectNextArticle, isTrue);

    await controller.selectAdjacentArticle(1);
    expect(controller.canSelectPreviousArticle, isTrue);
    expect(controller.canSelectNextArticle, isFalse);
  });

  test('clear read articles removes read entries', () async {
    final controller = ReaderController(
      repository: ReaderRepository.memory(
        initialSnapshotJson: _snapshotWithTwoArticles,
      ),
    );
    await controller.load();
    final firstId = controller.articles.first.id;
    await controller.openArticle(firstId);

    await controller.clearReadArticles();

    expect(controller.articles.length, 1);
    expect(controller.articles.first.isRead, isFalse);
  });

  // --- Settings -------------------------------------------------------------

  test('theme mode and font scale persist across reload', () async {
    final repository = ReaderRepository.memory();
    final controller = ReaderController(repository: repository);
    await controller.load();

    controller.themeMode = ThemeMode.dark;
    controller.readingFontScale = 1.3;
    // Allow async best-effort persistence to complete.
    await Future.delayed(Duration.zero);

    final reloaded = ReaderController(repository: repository);
    await reloaded.load();
    expect(reloaded.themeMode, ThemeMode.dark);
    expect(reloaded.readingFontScale, closeTo(1.3, 0.01));
  });

  // --- URL safety (component-guidelines) ------------------------------------

  test('only http/https URLs are treated as safe for external open', () {
    expect(isSafeExternalUrl(Uri.parse('https://example.com/a')), isTrue);
    expect(isSafeExternalUrl(Uri.parse('http://example.com/a')), isTrue);
    expect(isSafeExternalUrl(Uri.parse('javascript:alert(1)')), isFalse);
    expect(isSafeExternalUrl(Uri.parse('data:text/html,<script>')), isFalse);
    expect(isSafeExternalUrl(Uri.parse('file:///etc/passwd')), isFalse);
    expect(isSafeExternalUrl(Uri.parse('/relative/path')), isFalse);
  });

  // --- Widget smoke ---------------------------------------------------------

  testWidgets('app renders the empty state with no feeds', (tester) async {
    final controller = ReaderController(repository: ReaderRepository.memory());
    await controller.load();

    await tester.pumpWidget(MyApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('Rust RSS Reader'), findsOneWidget);
    expect(find.text('No feeds yet'), findsOneWidget);
  });
}

/// Snapshot fixture with one feed and two articles (newest first after sort).
const _snapshotWithTwoArticles = '''
{"feeds":[{"id":"feed-snap-1","title":"Example Feed","sourceUrl":"https://example.com/feed.xml","siteUrl":"https://example.com","description":"","unreadCount":2,"articleCount":2,"lastSyncedAt":null,"lastError":null,"errorCount":0}],"articles":[{"id":"art-newer","feedId":"feed-snap-1","title":"Newer story","url":"https://example.com/2","author":"","summary":"Second","content":"","publishedAt":"2026-06-17T11:00:00Z","isRead":false,"isStarred":false},{"id":"art-older","feedId":"feed-snap-1","title":"Older story","url":"https://example.com/1","author":"","summary":"First","content":"","publishedAt":"2026-06-17T10:00:00Z","isRead":false,"isStarred":false}],"lastUpdatedAt":null}''';

class _MockRustApi implements RustLibApi {
  final List<Feed> _dbFeeds = [];
  int _feedCounter = 0;

  /// Clears DB-backed feed state so each test starts from an empty feed list.
  void reset() {
    _dbFeeds.clear();
    _feedCounter = 0;
  }

  /// P0b added the SQLite-backed feed/entry/category APIs to `RustLibApi`.
  /// Unimplemented members fall through to `noSuchMethod`.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  // --- DB-backed feed API (P1a) --------------------------------------------

  @override
  Future<List<Feed>> crateApiFeedListFeeds() async => List<Feed>.from(_dbFeeds);

  @override
  Future<Feed> crateApiFeedSubscribeFeed({required String url}) async {
    // Idempotent: return the existing record for the same source URL.
    final existing = _dbFeeds.where((feed) => feed.sourceUrl == url).toList();
    if (existing.isNotEmpty) {
      return existing.first;
    }
    final uri = Uri.tryParse(url);
    final feed = Feed(
      id: 'feed-${++_feedCounter}',
      title: uri?.host ?? url,
      sourceUrl: url,
      siteUrl: uri != null ? '${uri.scheme}://${uri.host}' : '',
      description: '',
      unreadCount: 0,
      articleCount: 0,
      lastSyncedAt: DateTime.now().toUtc().toIso8601String(),
      articleViewMode: ArticleViewMode.global,
      lastError: null,
      errorCount: 0,
    );
    _dbFeeds.add(feed);
    return feed;
  }

  @override
  Future<List<FeedCandidate>> crateApiFeedDiscoverFeeds({
    required String url,
  }) async {
    return [FeedCandidate(url: url, title: null, mimeType: null)];
  }

  @override
  Future<void> crateApiFeedDeleteFeed({required String feedId}) async {
    _dbFeeds.removeWhere((feed) => feed.id == feedId);
  }

  @override
  Future<void> crateApiFeedSetFeedViewMode({
    required String feedId,
    required ArticleViewMode viewMode,
  }) async {
    final index = _dbFeeds.indexWhere((feed) => feed.id == feedId);
    if (index < 0) return;
    final old = _dbFeeds[index];
    _dbFeeds[index] = Feed(
      id: old.id,
      title: old.title,
      sourceUrl: old.sourceUrl,
      siteUrl: old.siteUrl,
      description: old.description,
      unreadCount: old.unreadCount,
      articleCount: old.articleCount,
      lastSyncedAt: old.lastSyncedAt,
      articleViewMode: viewMode,
      lastError: old.lastError,
      errorCount: old.errorCount,
    );
  }

  // --- Legacy snapshot API (entry reading UI, unchanged until P2a) ----------

  @override
  String crateApiReaderEmptyReaderSnapshotJson() =>
      jsonEncode({'feeds': [], 'articles': [], 'lastUpdatedAt': null});

  @override
  ReaderSnapshot crateApiReaderDecodeReaderSnapshot({
    required String snapshotJson,
  }) =>
      _snapshotFromJson(snapshotJson);

  @override
  List<ArticleListItem> crateApiReaderListArticles({
    required String snapshotJson,
    String? feedId,
    required bool showStarredOnly,
    required bool showUnreadOnly,
  }) {
    final snapshot = _snapshotFromJson(snapshotJson);
    final feedsById = {for (final feed in snapshot.feeds) feed.id: feed.title};
    final items = snapshot.articles
        .where((article) {
          final feedMatches = feedId == null || article.feedId == feedId;
          final starredMatches = !showStarredOnly || article.isStarred;
          final unreadMatches = !showUnreadOnly || !article.isRead;
          return feedMatches && starredMatches && unreadMatches;
        })
        .map((article) => ArticleListItem(
              id: article.id,
              feedId: article.feedId,
              feedTitle: feedsById[article.feedId] ?? 'Unknown Feed',
              title: article.title,
              summary: article.summary,
              publishedAt: article.publishedAt,
              isRead: article.isRead,
              isStarred: article.isStarred,
            ))
        .toList();

    items.sort((left, right) {
      final leftPublished = left.publishedAt ?? '';
      final rightPublished = right.publishedAt ?? '';
      return rightPublished.compareTo(leftPublished);
    });
    return items;
  }

  @override
  Article crateApiReaderGetArticle({
    required String snapshotJson,
    required String articleId,
  }) {
    final snapshot = _snapshotFromJson(snapshotJson);
    return snapshot.articles.firstWhere((article) => article.id == articleId);
  }

  @override
  String crateApiReaderMarkArticleRead({
    required String snapshotJson,
    required String articleId,
    required bool isRead,
  }) {
    final snapshot = _jsonMap(snapshotJson);
    final articles =
        List<Map<String, dynamic>>.from(snapshot['articles'] as List).map(
            (article) {
      if (article['id'] == articleId) {
        return {...article, 'isRead': isRead};
      }
      return article;
    }).toList();
    snapshot['articles'] = articles;
    return _recountEncoded(snapshot);
  }

  @override
  String crateApiReaderToggleArticleStar({
    required String snapshotJson,
    required String articleId,
  }) {
    final snapshot = _jsonMap(snapshotJson);
    final articles =
        List<Map<String, dynamic>>.from(snapshot['articles'] as List).map(
            (article) {
      if (article['id'] == articleId) {
        return {...article, 'isStarred': !(article['isStarred'] as bool)};
      }
      return article;
    }).toList();
    snapshot['articles'] = articles;
    return jsonEncode(snapshot);
  }

  @override
  String crateApiReaderClearAllReadArticles({required String snapshotJson}) {
    final snapshot = _jsonMap(snapshotJson);
    final articles = List<Map<String, dynamic>>.from(
      snapshot['articles'] as List,
    )..removeWhere((article) => article['isRead'] == true);
    snapshot['articles'] = articles;
    return _recountEncoded(snapshot);
  }

  @override
  Future<ArticleViewMode> crateApiReaderArticleViewModeDefault() async =>
      ArticleViewMode.global;

  @override
  Future<void> crateApiAppInitApp() async {}

  @override
  String crateApiAppGreet({required String name}) => 'Hello, $name!';

  @override
  String crateApiAppAppVersion() => '0.1.0';

  ArticleViewMode _viewModeFromName(String? name) {
    switch (name) {
      case 'webpage':
        return ArticleViewMode.webpage;
      case 'rendered':
        return ArticleViewMode.rendered;
      case 'external':
      case 'external_':
        return ArticleViewMode.external_;
      case 'global':
      default:
        return ArticleViewMode.global;
    }
  }

  Map<String, dynamic> _jsonMap(String snapshotJson) {
    if (snapshotJson.trim().isEmpty) {
      return {
        'feeds': <Map<String, dynamic>>[],
        'articles': <Map<String, dynamic>>[],
        'lastUpdatedAt': null,
      };
    }
    return Map<String, dynamic>.from(jsonDecode(snapshotJson) as Map);
  }

  String _recountEncoded(Map<String, dynamic> snapshot) {
    final feeds = List<Map<String, dynamic>>.from(snapshot['feeds'] as List);
    final articles =
        List<Map<String, dynamic>>.from(snapshot['articles'] as List);

    final recountedFeeds = feeds.map((feed) {
      final feedArticles = articles
          .where((article) => article['feedId'] == feed['id'])
          .toList();
      final unreadCount = feedArticles
          .where((article) => article['isRead'] != true)
          .length;
      return {
        ...feed,
        'articleCount': feedArticles.length,
        'unreadCount': unreadCount,
      };
    }).toList();

    snapshot['feeds'] = recountedFeeds;
    return jsonEncode(snapshot);
  }

  ReaderSnapshot _snapshotFromJson(String snapshotJson) {
    final decoded = _jsonMap(snapshotJson);
    return ReaderSnapshot(
      feeds: (decoded['feeds'] as List<dynamic>? ?? const [])
          .map((value) => Feed(
                id: value['id'] as String,
                title: value['title'] as String,
                sourceUrl: value['sourceUrl'] as String,
                siteUrl: value['siteUrl'] as String,
                description: value['description'] as String,
                unreadCount: value['unreadCount'] as int,
                articleCount: value['articleCount'] as int,
                lastSyncedAt: value['lastSyncedAt'] as String?,
                articleViewMode:
                    _viewModeFromName(value['articleViewMode'] as String?),
                lastError: value['lastError'] as String?,
                errorCount: value['errorCount'] as int? ?? 0,
              ))
          .toList(),
      articles: (decoded['articles'] as List<dynamic>? ?? const [])
          .map((value) => Article(
                id: value['id'] as String,
                feedId: value['feedId'] as String,
                title: value['title'] as String,
                url: value['url'] as String,
                author: value['author'] as String,
                summary: value['summary'] as String,
                content: value['content'] as String,
                publishedAt: value['publishedAt'] as String?,
                isRead: value['isRead'] as bool,
                isStarred: value['isStarred'] as bool,
              ))
          .toList(),
      lastUpdatedAt: decoded['lastUpdatedAt'] as String?,
    );
  }
}
