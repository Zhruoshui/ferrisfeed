import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rss_reader/src/rust/api/reader.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef SnapshotReader = Future<String?> Function();
typedef SnapshotWriter = Future<void> Function(String snapshotJson);

class ReaderRepository {
  ReaderRepository._(
    this._readSnapshot,
    this._writeSnapshot, {
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  static const _snapshotStorageKey = 'reader_snapshot_v1';
  static const _requestTimeout = Duration(seconds: 20);

  final SnapshotReader _readSnapshot;
  final SnapshotWriter _writeSnapshot;
  final http.Client _httpClient;

  static Future<ReaderRepository> create({http.Client? httpClient}) async {
    final preferences = await SharedPreferences.getInstance();
    return ReaderRepository._(
      () async => preferences.getString(_snapshotStorageKey),
      (snapshotJson) async {
        await preferences.setString(_snapshotStorageKey, snapshotJson);
      },
      httpClient: httpClient,
    );
  }

  factory ReaderRepository.memory({
    String? initialSnapshotJson,
    http.Client? httpClient,
  }) {
    var inMemorySnapshot = initialSnapshotJson;
    return ReaderRepository._(() async => inMemorySnapshot, (
      snapshotJson,
    ) async {
      inMemorySnapshot = snapshotJson;
    }, httpClient: httpClient);
  }

  Future<String> loadSnapshotJson() async {
    final persisted = await _readSnapshot();
    if (persisted == null || persisted.trim().isEmpty) {
      return emptyReaderSnapshotJson();
    }
    return persisted;
  }

  Future<void> saveSnapshotJson(String snapshotJson) {
    return _writeSnapshot(snapshotJson);
  }

  Future<ImportFeedResult> importFeed({
    required String snapshotJson,
    required String feedUrl,
  }) async {
    final response = await _httpClient
        .get(
          Uri.parse(feedUrl),
          headers: const {
            'accept':
                'application/rss+xml, application/atom+xml, application/xml, text/xml;q=0.9, */*;q=0.8',
            'user-agent': 'rss_reader/1.0 (flutter)',
          },
        )
        .timeout(_requestTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ReaderAppException(
        'Failed to fetch feed: HTTP ${response.statusCode}',
      );
    }

    final xmlContent = utf8.decode(response.bodyBytes);
    if (xmlContent.trim().isEmpty) {
      throw const ReaderAppException('The feed response was empty.');
    }

    return importFeedFromXml(
      snapshotJson: snapshotJson,
      feedUrl: feedUrl,
      xmlContent: xmlContent,
    );
  }

  void dispose() {
    _httpClient.close();
  }
}

class ReaderAppException implements Exception {
  const ReaderAppException(this.message);

  final String message;

  @override
  String toString() => message;
}
