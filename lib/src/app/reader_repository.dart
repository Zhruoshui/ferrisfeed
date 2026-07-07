import 'dart:async';

import 'package:rss_reader/src/rust/api/reader.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef SnapshotReader = Future<String?> Function();
typedef SnapshotWriter = Future<void> Function(String snapshotJson);
typedef SettingReader = Future<String?> Function(String key);
typedef SettingWriter = Future<void> Function(String key, String value);

/// Persists the in-memory reader snapshot (still used by the entry-reading UI
/// until P2a) and app settings.
///
/// P1a moved feed HTTP fetching into Rust (`api::feed::subscribe_feed`), so
/// this class no longer performs any network I/O — it only reads/writes the
/// snapshot blob and key/value settings via `shared_preferences`.
class ReaderRepository {
  ReaderRepository._(
    this._readSnapshot,
    this._writeSnapshot, {
    SettingReader? readSetting,
    SettingWriter? writeSetting,
  })  : _readSetting = readSetting ?? ((_) async => null),
        _writeSetting = writeSetting ?? ((_, _) async {});

  static const _snapshotStorageKey = 'reader_snapshot_v1';
  static const _settingPrefix = 'reader_setting_';

  final SnapshotReader _readSnapshot;
  final SnapshotWriter _writeSnapshot;
  final SettingReader _readSetting;
  final SettingWriter _writeSetting;

  static Future<ReaderRepository> create() async {
    final preferences = await SharedPreferences.getInstance();
    return ReaderRepository._(
      () async => preferences.getString(_snapshotStorageKey),
      (snapshotJson) async {
        await preferences.setString(_snapshotStorageKey, snapshotJson);
      },
      readSetting: (key) async => preferences.getString('$_settingPrefix$key'),
      writeSetting: (key, value) async {
        await preferences.setString('$_settingPrefix$key', value);
      },
    );
  }

  factory ReaderRepository.memory({String? initialSnapshotJson}) {
    var inMemorySnapshot = initialSnapshotJson;
    final inMemorySettings = <String, String>{};
    return ReaderRepository._(
      () async => inMemorySnapshot,
      (snapshotJson) async {
        inMemorySnapshot = snapshotJson;
      },
      readSetting: (key) async => inMemorySettings[key],
      writeSetting: (key, value) async {
        inMemorySettings[key] = value;
      },
    );
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

  Future<String?> getSetting(String key) {
    return _readSetting(key);
  }

  Future<void> setSetting(String key, String value) {
    return _writeSetting(key, value);
  }

  void dispose() {}
}

class ReaderAppException implements Exception {
  const ReaderAppException(this.message);

  final String message;

  @override
  String toString() => message;
}
