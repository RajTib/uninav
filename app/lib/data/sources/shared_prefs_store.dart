import 'package:shared_preferences/shared_preferences.dart';

import '../../core/storage/key_value_store.dart';

/// Production [KeyValueStore] backed by shared_preferences. Constructed in
/// main() after `SharedPreferences.getInstance()` so every read afterwards
/// is synchronous — no async plumbing leaks into providers.
final class SharedPrefsStore implements KeyValueStore {
  const SharedPrefsStore(this._prefs);

  final SharedPreferences _prefs;

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);

  @override
  Future<void> remove(String key) => _prefs.remove(key);
}
