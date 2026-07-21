/// Tiny persistence seam. The app's local state (prefs, favorites, recents)
/// needs only string get/set — so that's the whole interface. The default
/// provider binding is [InMemoryKeyValueStore]; main() overrides it with the
/// shared_preferences implementation at bootstrap. Tests therefore get
/// hermetic in-memory persistence with zero mocking ceremony.
abstract interface class KeyValueStore {
  String? getString(String key);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
}

final class InMemoryKeyValueStore implements KeyValueStore {
  InMemoryKeyValueStore([Map<String, String>? seed])
      : _map = {...?seed};

  final Map<String, String> _map;

  @override
  String? getString(String key) => _map[key];

  @override
  Future<void> setString(String key, String value) async => _map[key] = value;

  @override
  Future<void> remove(String key) async => _map.remove(key);
}
