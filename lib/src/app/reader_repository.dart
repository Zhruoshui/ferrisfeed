import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

typedef SettingReader = Future<String?> Function(String key);
typedef SettingWriter = Future<void> Function(String key, String value);

/// Persists app settings (font scale, theme, default view mode) via
/// `shared_preferences`.
///
/// The JSON-snapshot blob that previously held in-memory reader state has been
/// removed (P2a): the reading UI now reads entries directly from the persisted
/// SQLite database through the FRB entry API, so there is no snapshot to store.
class ReaderRepository {
  ReaderRepository._({
    SettingReader? readSetting,
    SettingWriter? writeSetting,
  })  : _readSetting = readSetting ?? ((_) async => null),
        _writeSetting = writeSetting ?? ((_, _) async {});

  static const _settingPrefix = 'reader_setting_';

  final SettingReader _readSetting;
  final SettingWriter _writeSetting;

  static Future<ReaderRepository> create() async {
    final preferences = await SharedPreferences.getInstance();
    return ReaderRepository._(
      readSetting: (key) async => preferences.getString('$_settingPrefix$key'),
      writeSetting: (key, value) async {
        await preferences.setString('$_settingPrefix$key', value);
      },
    );
  }

  factory ReaderRepository.memory() {
    final inMemorySettings = <String, String>{};
    return ReaderRepository._(
      readSetting: (key) async => inMemorySettings[key],
      writeSetting: (key, value) async {
        inMemorySettings[key] = value;
      },
    );
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
