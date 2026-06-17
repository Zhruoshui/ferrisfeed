import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rss_reader/main.dart';
import 'package:rss_reader/src/app/reader_controller.dart';
import 'package:rss_reader/src/app/reader_repository.dart';
import 'package:rss_reader/src/rust/api/reader.dart';
import 'package:rss_reader/src/rust/frb_generated.dart';

void main() {
  setUpAll(() {
    RustLib.initMock(api: _MockRustApi());
  });

  testWidgets('renders imported feed content', (tester) async {
    final controller = ReaderController(
      repository: ReaderRepository.memory(
        httpClient: _FakeHttpClient(
          responses: {
            Uri.parse('https://example.com/feed.xml'): http.Response.bytes(
              Uint8List.fromList(_sampleFeed.codeUnits),
              200,
              headers: const {'content-type': 'application/rss+xml'},
            ),
          },
        ),
      ),
    );

    await controller.load();
    await controller.addFeed('https://example.com/feed.xml');

    await tester.pumpWidget(MyApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('Rust RSS Reader'), findsOneWidget);
    expect(find.text('Example Feed'), findsWidgets);
    expect(find.text('First story'), findsOneWidget);
  });
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient({required this.responses});

  final Map<Uri, http.Response> responses;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = responses[request.url];
    if (response == null) {
      throw StateError('Unexpected request for ${request.url}');
    }

    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([response.bodyBytes]),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: request,
    );
  }
}

class _MockRustApi implements RustLibApi {
  int _feedCounter = 0;
  int _articleCounter = 0;

  @override
  String crateApiReaderEmptyReaderSnapshotJson() =>
      jsonEncode({'feeds': [], 'articles': [], 'lastUpdatedAt': null});

  @override
  ReaderSnapshot crateApiReaderDecodeReaderSnapshot({
    required String snapshotJson,
  }) {
    return _snapshotFromJson(snapshotJson);
  }

  @override
  List<ArticleListItem> crateApiReaderListArticles({
    required String snapshotJson,
    String? feedId,
    required bool showStarredOnly,
  }) {
    final snapshot = _snapshotFromJson(snapshotJson);
    final feedsById = {for (final feed in snapshot.feeds) feed.id: feed.title};
    final items = snapshot.articles
        .where((article) {
          final feedMatches = feedId == null || article.feedId == feedId;
          final starredMatches = !showStarredOnly || article.isStarred;
          return feedMatches && starredMatches;
        })
        .map((article) {
          return ArticleListItem(
            id: article.id,
            feedId: article.feedId,
            feedTitle: feedsById[article.feedId] ?? 'Unknown Feed',
            title: article.title,
            summary: article.summary,
            publishedAt: article.publishedAt,
            isRead: article.isRead,
            isStarred: article.isStarred,
          );
        })
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
  String crateApiReaderAddFeed({
    required String snapshotJson,
    required FeedDraft draft,
  }) {
    final snapshot = _jsonMap(snapshotJson);
    final feeds = List<Map<String, dynamic>>.from(snapshot['feeds'] as List);
    feeds.add({
      'id': 'feed-${++_feedCounter}',
      'title': draft.title,
      'sourceUrl': draft.sourceUrl,
      'siteUrl': draft.siteUrl,
      'description': draft.description,
      'unreadCount': 0,
      'articleCount': 0,
      'lastSyncedAt': null,
    });
    snapshot['feeds'] = feeds;
    return jsonEncode(snapshot);
  }

  @override
  String crateApiReaderRemoveFeed({
    required String snapshotJson,
    required String feedId,
  }) {
    final snapshot = _jsonMap(snapshotJson);
    final feeds = List<Map<String, dynamic>>.from(snapshot['feeds'] as List)
      ..removeWhere((feed) => feed['id'] == feedId);
    final articles = List<Map<String, dynamic>>.from(
      snapshot['articles'] as List,
    )..removeWhere((article) => article['feedId'] == feedId);
    snapshot['feeds'] = feeds;
    snapshot['articles'] = articles;
    return _recountEncoded(snapshot);
  }

  @override
  String crateApiReaderMarkArticleRead({
    required String snapshotJson,
    required String articleId,
    required bool isRead,
  }) {
    final snapshot = _jsonMap(snapshotJson);
    final articles =
        List<Map<String, dynamic>>.from(snapshot['articles'] as List).map((
          article,
        ) {
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
        List<Map<String, dynamic>>.from(snapshot['articles'] as List).map((
          article,
        ) {
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
  Future<ImportFeedResult> crateApiReaderImportFeedFromXml({
    required String snapshotJson,
    required String feedUrl,
    required String xmlContent,
  }) async {
    final snapshot = _jsonMap(snapshotJson);
    final parsed = _parseFeedXml(feedUrl, xmlContent);

    final feeds = List<Map<String, dynamic>>.from(snapshot['feeds'] as List)
      ..removeWhere((feed) => feed['sourceUrl'] == feedUrl);

    final feedId = 'feed-${++_feedCounter}';
    final feedMap = <String, dynamic>{
      'id': feedId,
      'title': parsed.title,
      'sourceUrl': feedUrl,
      'siteUrl': parsed.siteUrl,
      'description': parsed.description,
      'unreadCount': 0,
      'articleCount': 0,
      'lastSyncedAt': DateTime.now().toUtc().toIso8601String(),
    };
    feeds.add(feedMap);

    final articles = List<Map<String, dynamic>>.from(
      snapshot['articles'] as List,
    );
    final inserted = <Map<String, dynamic>>[];
    for (final item in parsed.items) {
      if (articles.any((article) => article['url'] == item.url)) {
        continue;
      }
      final article = <String, dynamic>{
        'id': 'article-${++_articleCounter}',
        'feedId': feedId,
        'title': item.title,
        'url': item.url,
        'author': item.author,
        'summary': item.summary,
        'content': item.content,
        'publishedAt': item.publishedAt,
        'isRead': false,
        'isStarred': false,
      };
      articles.add(article);
      inserted.add(article);
    }

    snapshot['feeds'] = feeds;
    snapshot['articles'] = articles;
    final encoded = _recountEncoded(snapshot);
    final decoded = _snapshotFromJson(encoded);
    final feed = decoded.feeds.firstWhere((value) => value.id == feedId);
    final insertedArticles = decoded.articles
        .where((article) => inserted.any((item) => item['id'] == article.id))
        .toList();

    return ImportFeedResult(
      snapshotJson: encoded,
      feed: feed,
      insertedArticles: insertedArticles,
    );
  }

  @override
  Future<void> crateApiSimpleInitApp() async {}

  @override
  String crateApiSimpleGreet({required String name}) => 'Hello, $name!';

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
    final articles = List<Map<String, dynamic>>.from(
      snapshot['articles'] as List,
    );

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
          .map(
            (value) => Feed(
              id: value['id'] as String,
              title: value['title'] as String,
              sourceUrl: value['sourceUrl'] as String,
              siteUrl: value['siteUrl'] as String,
              description: value['description'] as String,
              unreadCount: value['unreadCount'] as int,
              articleCount: value['articleCount'] as int,
              lastSyncedAt: value['lastSyncedAt'] as String?,
            ),
          )
          .toList(),
      articles: (decoded['articles'] as List<dynamic>? ?? const [])
          .map(
            (value) => Article(
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
            ),
          )
          .toList(),
      lastUpdatedAt: decoded['lastUpdatedAt'] as String?,
    );
  }

  _ParsedFeed _parseFeedXml(String feedUrl, String xmlContent) {
    final title =
        _firstTag(xmlContent, 'channel', 'title') ??
        _firstTag(xmlContent, null, 'title') ??
        feedUrl;
    final description = _firstTag(xmlContent, 'channel', 'description') ?? '';
    final siteUrl = _firstTag(xmlContent, 'channel', 'link') ?? feedUrl;
    final items = _extractBlocks(xmlContent, 'item')
        .map(
          (item) => _ParsedItem(
            title: _firstTag(item, null, 'title') ?? 'Untitled Article',
            url: _firstTag(item, null, 'link') ?? '',
            author: _firstTag(item, null, 'author') ?? '',
            summary: _firstTag(item, null, 'description') ?? '',
            content:
                _firstTag(item, null, 'content:encoded') ??
                _firstTag(item, null, 'description') ??
                '',
            publishedAt: _firstTag(item, null, 'pubDate'),
          ),
        )
        .where((item) => item.url.isNotEmpty)
        .toList();
    return _ParsedFeed(
      title: title,
      description: description,
      siteUrl: siteUrl,
      items: items,
    );
  }

  List<String> _extractBlocks(String input, String tag) {
    final matches = RegExp(
      '<$tag[^>]*>([\\s\\S]*?)</$tag>',
      caseSensitive: false,
    ).allMatches(input);
    return matches.map((match) => match.group(1) ?? '').toList();
  }

  String? _firstTag(String input, String? outerTag, String innerTag) {
    final scope = outerTag == null
        ? input
        : (_extractBlocks(input, outerTag).isNotEmpty
              ? _extractBlocks(input, outerTag).first
              : '');
    final match = RegExp(
      '<$innerTag[^>]*>([\\s\\S]*?)</$innerTag>',
      caseSensitive: false,
    ).firstMatch(scope);
    if (match == null) {
      return null;
    }
    return _cleanText(match.group(1) ?? '');
  }

  String _cleanText(String value) {
    return value
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .trim();
  }
}

class _ParsedFeed {
  _ParsedFeed({
    required this.title,
    required this.description,
    required this.siteUrl,
    required this.items,
  });

  final String title;
  final String description;
  final String siteUrl;
  final List<_ParsedItem> items;
}

class _ParsedItem {
  _ParsedItem({
    required this.title,
    required this.url,
    required this.author,
    required this.summary,
    required this.content,
    required this.publishedAt,
  });

  final String title;
  final String url;
  final String author;
  final String summary;
  final String content;
  final String? publishedAt;
}

const _sampleFeed = '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Example Feed</title>
    <link>https://example.com</link>
    <description>Example stories</description>
    <item>
      <title>First story</title>
      <link>https://example.com/articles/1</link>
      <description>Hello from the feed</description>
      <pubDate>Wed, 17 Jun 2026 10:00:00 GMT</pubDate>
    </item>
  </channel>
</rss>
''';
