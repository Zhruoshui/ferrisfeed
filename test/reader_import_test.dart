import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rss_reader/main.dart';
import 'package:rss_reader/src/app/article_detail_view.dart';
import 'package:rss_reader/src/app/reader_controller.dart';
import 'package:rss_reader/src/app/reader_repository.dart';
import 'package:rss_reader/src/rust/api/error.dart';
import 'package:rss_reader/src/rust/api/types.dart';
import 'package:rss_reader/src/rust/frb_generated.dart';

void main() {
  // A single mock is installed once (FRB holds it as a static singleton); its
  // DB-backed feed + entry state is reset before each test so tests are
  // isolated.
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

  // --- Entry reading (persisted, P2a) ---------------------------------------
  //
  // These seed entries directly into the mock's in-memory store (the path the
  // sync would populate) and exercise the controller's persisted entry flow:
  // list filters, read-on-open, star toggle, and prev/next navigation.

  test('unread filter shows only unread entries', () async {
    final controller = ReaderController(repository: ReaderRepository.memory());
    await controller.load();
    await controller.subscribeFeed('https://example.com/feed.xml');
    final feedId = controller.feeds.first.id;
    mockApi.seedEntry(feedId, title: 'Newer', url: 'https://a/2',
        publishedAt: DateTime.utc(2026, 6, 17, 11));
    mockApi.seedEntry(feedId, title: 'Older', url: 'https://a/1',
        publishedAt: DateTime.utc(2026, 6, 17, 10));

    await controller.showAllArticles();
    expect(controller.articles.length, 2);

    // Opening the newest entry marks it read.
    final firstId = controller.articles.first.id;
    await controller.openArticle(firstId);
    expect(controller.selectedArticle?.isRead, isTrue);

    await controller.showUnreadArticles();
    expect(controller.articles.length, 1);
    expect(controller.articles.first.isRead, isFalse);
  });

  test('adjacent entry navigation moves within the list', () async {
    final controller = ReaderController(repository: ReaderRepository.memory());
    await controller.load();
    await controller.subscribeFeed('https://example.com/feed.xml');
    final feedId = controller.feeds.first.id;
    mockApi.seedEntry(feedId, title: 'Older', url: 'https://a/1',
        publishedAt: DateTime.utc(2026, 6, 17, 10));
    mockApi.seedEntry(feedId, title: 'Newer', url: 'https://a/2',
        publishedAt: DateTime.utc(2026, 6, 17, 11));

    // newest-first: [Newer, Older]. After load no entry is selected yet.
    await controller.showAllArticles();
    expect(controller.canSelectPreviousArticle, isFalse);
    expect(controller.canSelectNextArticle, isFalse);

    // Open the newest (index 0): no prev (nothing newer), next is Older.
    await controller.openArticle(controller.articles.first.id);
    expect(controller.canSelectPreviousArticle, isFalse);
    expect(controller.canSelectNextArticle, isTrue);

    // Move to the next (older) entry.
    await controller.selectAdjacentArticle(1);
    expect(controller.canSelectPreviousArticle, isTrue);
    expect(controller.canSelectNextArticle, isFalse);
  });

  test('star toggle persists the new state', () async {
    final controller = ReaderController(repository: ReaderRepository.memory());
    await controller.load();
    await controller.subscribeFeed('https://example.com/feed.xml');
    final feedId = controller.feeds.first.id;
    mockApi.seedEntry(feedId, title: 'Star me', url: 'https://a/1',
        publishedAt: DateTime.utc(2026, 6, 17, 10));

    await controller.showAllArticles();
    await controller.openArticle(controller.articles.first.id);
    expect(controller.selectedArticle?.isStarred, isFalse);

    await controller.toggleSelectedArticleStar();
    expect(controller.selectedArticle?.isStarred, isTrue);
    expect(controller.articles.first.isStarred, isTrue);

    await controller.toggleSelectedArticleStar();
    expect(controller.selectedArticle?.isStarred, isFalse);
  });

  test('starred filter shows only starred entries', () async {
    final controller = ReaderController(repository: ReaderRepository.memory());
    await controller.load();
    await controller.subscribeFeed('https://example.com/feed.xml');
    final feedId = controller.feeds.first.id;
    mockApi.seedEntry(feedId, title: 'Plain', url: 'https://a/1',
        publishedAt: DateTime.utc(2026, 6, 17, 10));
    final starredId = mockApi.seedEntry(feedId, title: 'Loved', url: 'https://a/2',
        publishedAt: DateTime.utc(2026, 6, 17, 11), isStarred: true);

    await controller.showStarredArticles();
    expect(controller.articles.length, 1);
    expect(controller.articles.first.id, starredId);
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

/// In-memory mock of the FRB `RustLibApi`. Mirrors the persisted feed + entry
/// behaviour closely enough to exercise the controller's reading flow without a
/// real SQLite database: feeds and entries live in lists, and the entry
/// list/get/mark-read/star/adjacent methods reproduce the Rust query semantics
/// (newest-first ordering, filters, pagination, prev/next neighbours).
class _MockRustApi implements RustLibApi {
  final List<Feed> _dbFeeds = [];
  final List<Entry> _entries = [];
  int _feedCounter = 0;
  int _entryCounter = 0;

  void reset() {
    _dbFeeds.clear();
    _entries.clear();
    _feedCounter = 0;
    _entryCounter = 0;
  }

  /// Seeds an entry for [feedId] into the mock store and returns its id.
  String seedEntry(
    String feedId, {
    required String title,
    required String url,
    required DateTime publishedAt,
    bool isRead = false,
    bool isStarred = false,
    String? content,
  }) {
    final id = 'entry-${++_entryCounter}';
    final now = DateTime.now().toUtc();
    _entries.add(Entry(
      id: id,
      feedId: feedId,
      title: title,
      url: url,
      content: content,
      summary: null,
      author: null,
      imageUrl: null,
      publishedAt: publishedAt,
      isRead: isRead,
      isStarred: isStarred,
      readProgress: null,
      createdAt: now,
    ));
    _recountFeed(feedId);
    return id;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  // --- DB-backed feed API (P1a) --------------------------------------------

  @override
  Future<List<Feed>> crateApiFeedListFeeds() async => List<Feed>.from(_dbFeeds);

  @override
  Future<Feed> crateApiFeedSubscribeFeed({required String url}) async {
    final existing = _dbFeeds.where((feed) => feed.sourceUrl == url).toList();
    if (existing.isNotEmpty) {
      return existing.first;
    }
    final uri = Uri.tryParse(url);
    final now = DateTime.now().toUtc();
    final feed = Feed(
      id: 'feed-${++_feedCounter}',
      title: uri?.host ?? url,
      sourceUrl: url,
      siteUrl: uri != null ? '${uri.scheme}://${uri.host}' : null,
      description: null,
      imageUrl: null,
      folder: null,
      category: null,
      articleViewMode: ArticleViewMode.global,
      unreadCount: 0,
      articleCount: 0,
      lastSyncedAt: now,
      lastError: null,
      errorCount: 0,
      etag: null,
      lastModified: null,
      createdAt: now,
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
    _entries.removeWhere((entry) => entry.feedId == feedId);
  }

  @override
  Future<void> crateApiFeedSetFeedViewMode({
    required String feedId,
    required ArticleViewMode viewMode,
  }) async {
    final index = _dbFeeds.indexWhere((feed) => feed.id == feedId);
    if (index < 0) return;
    _dbFeeds[index] = _copyFeed(_dbFeeds[index], articleViewMode: viewMode);
  }

  @override
  Stream<SyncProgress> crateApiFeedRefreshAllFeeds() async* {
    final total = _dbFeeds.length;
    var completed = 0;
    for (final feed in _dbFeeds) {
      completed += 1;
      yield SyncProgress(
        total: total,
        completed: completed,
        failed: 0,
        feedId: feed.id,
        feedTitle: feed.title,
        newEntries: 0,
        totalNewEntries: 0,
        done: false,
        error: null,
      );
    }
    yield SyncProgress(
      total: total,
      completed: completed,
      failed: 0,
      feedId: null,
      feedTitle: null,
      newEntries: 0,
      totalNewEntries: 0,
      done: true,
      error: null,
    );
  }

  // --- Persisted entry API (P2a) -------------------------------------------

  @override
  Future<List<EntryListItem>> crateApiEntryListEntries({
    String? feedId,
    required bool unreadOnly,
    required bool starredOnly,
    required int limit,
    required int offset,
  }) async {
    final feedTitles = {for (final f in _dbFeeds) f.id: f.title};
    var items = _entries.where((e) {
      final feedMatches = feedId == null || e.feedId == feedId;
      final unreadMatches = !unreadOnly || !e.isRead;
      final starredMatches = !starredOnly || e.isStarred;
      return feedMatches && unreadMatches && starredMatches;
    }).toList()
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    final page = items.skip(offset).take(limit).toList();
    return page
        .map((e) => EntryListItem(
              id: e.id,
              feedId: e.feedId,
              feedTitle: feedTitles[e.feedId] ?? 'Unknown Feed',
              title: e.title,
              summary: e.summary ?? '',
              publishedAt: e.publishedAt,
              isRead: e.isRead,
              isStarred: e.isStarred,
            ))
        .toList();
  }

  @override
  Future<Entry> crateApiEntryGetEntry({required String entryId}) async {
    final entry = _entries.where((e) => e.id == entryId).firstOrNull;
    if (entry == null) {
      throw AppError_NotFound(resource: 'entry', id: entryId);
    }
    return entry;
  }

  @override
  Future<void> crateApiEntryMarkEntryRead({
    required String entryId,
    required bool isRead,
  }) async {
    final index = _entries.indexWhere((e) => e.id == entryId);
    if (index < 0) {
      throw AppError_NotFound(resource: 'entry', id: entryId);
    }
    _entries[index] = _copyEntry(_entries[index], isRead: isRead);
    _recountFeed(_entries[index].feedId);
  }

  @override
  Future<bool> crateApiEntryToggleEntryStar({required String entryId}) async {
    final index = _entries.indexWhere((e) => e.id == entryId);
    if (index < 0) {
      throw AppError_NotFound(resource: 'entry', id: entryId);
    }
    final nowStarred = !_entries[index].isStarred;
    _entries[index] = _copyEntry(_entries[index], isStarred: nowStarred);
    return nowStarred;
  }

  @override
  Future<AdjacentEntries> crateApiEntryGetAdjacentEntries({
    required String entryId,
    String? feedId,
    required bool unreadOnly,
    required bool starredOnly,
  }) async {
    // Reproduce the Rust semantics: newest-first ordering, prev = newer
    // neighbour, next = older neighbour, both within the filter context.
    final filtered = _entries.where((e) {
      final feedMatches = feedId == null || e.feedId == feedId;
      final unreadMatches = !unreadOnly || !e.isRead;
      final starredMatches = !starredOnly || e.isStarred;
      return feedMatches && unreadMatches && starredMatches;
    }).toList()
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

    final index = filtered.indexWhere((e) => e.id == entryId);
    if (index < 0) {
      return const AdjacentEntries(prev: null, next: null);
    }
    final prev = index > 0 ? filtered[index - 1].id : null;
    final next =
        index < filtered.length - 1 ? filtered[index + 1].id : null;
    return AdjacentEntries(prev: prev, next: next);
  }

  // --- App lifecycle -------------------------------------------------------

  @override
  Future<void> crateApiAppInitApp() async {}

  @override
  String crateApiAppGreet({required String name}) => 'Hello, $name!';

  @override
  String crateApiAppAppVersion() => '0.1.0';

  // --- helpers --------------------------------------------------------------

  void _recountFeed(String feedId) {
    final index = _dbFeeds.indexWhere((f) => f.id == feedId);
    if (index < 0) return;
    final feedEntries = _entries.where((e) => e.feedId == feedId);
    _dbFeeds[index] = _copyFeed(
      _dbFeeds[index],
      articleCount: feedEntries.length,
      unreadCount: feedEntries.where((e) => !e.isRead).length,
    );
  }

  Feed _copyFeed(
    Feed f, {
    ArticleViewMode? articleViewMode,
    int? unreadCount,
    int? articleCount,
  }) {
    return Feed(
      id: f.id,
      title: f.title,
      sourceUrl: f.sourceUrl,
      siteUrl: f.siteUrl,
      description: f.description,
      imageUrl: f.imageUrl,
      folder: f.folder,
      category: f.category,
      articleViewMode: articleViewMode ?? f.articleViewMode,
      unreadCount: unreadCount ?? f.unreadCount,
      articleCount: articleCount ?? f.articleCount,
      lastSyncedAt: f.lastSyncedAt,
      lastError: f.lastError,
      errorCount: f.errorCount,
      etag: f.etag,
      lastModified: f.lastModified,
      createdAt: f.createdAt,
    );
  }

  Entry _copyEntry(Entry e, {bool? isRead, bool? isStarred}) {
    return Entry(
      id: e.id,
      feedId: e.feedId,
      title: e.title,
      url: e.url,
      content: e.content,
      summary: e.summary,
      author: e.author,
      imageUrl: e.imageUrl,
      publishedAt: e.publishedAt,
      isRead: isRead ?? e.isRead,
      isStarred: isStarred ?? e.isStarred,
      readProgress: e.readProgress,
      createdAt: e.createdAt,
    );
  }
}
