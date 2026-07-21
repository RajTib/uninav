import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uninav/core/storage/key_value_store.dart';
import 'package:uninav/domain/services/routing/route_prefs.dart';
import 'package:uninav/features/search/presentation/search_controller.dart';
import 'package:uninav/features/settings/presentation/settings_providers.dart';

void main() {
  ProviderContainer containerWith(KeyValueStore store) {
    final container = ProviderContainer(
      overrides: [keyValueStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('AppPrefs persistence', () {
    test('defaults when nothing is stored', () {
      final c = containerWith(InMemoryKeyValueStore());
      final prefs = c.read(appPrefsProvider);
      expect(prefs.themeMode, ThemeMode.system);
      expect(prefs.defaultRouteMode, RouteMode.fastest);
    });

    test('writes survive a restart (new container, same store)', () async {
      final store = InMemoryKeyValueStore();
      final first = containerWith(store);
      first.read(appPrefsProvider.notifier)
        ..setThemeMode(ThemeMode.dark)
        ..setDefaultRouteMode(RouteMode.accessible);
      await Future<void>.delayed(Duration.zero); // let writes flush

      final second = containerWith(store);
      final restored = second.read(appPrefsProvider);
      expect(restored.themeMode, ThemeMode.dark);
      expect(restored.defaultRouteMode, RouteMode.accessible);
      expect(restored.routePrefs, RoutePrefs.accessible);
    });

    test('corrupt stored JSON falls back to defaults', () {
      final store = InMemoryKeyValueStore({'prefs.v1': '{not json'});
      final c = containerWith(store);
      expect(c.read(appPrefsProvider).themeMode, ThemeMode.system);
    });
  });

  group('favorites persistence', () {
    test('toggle on/off and restore', () async {
      final store = InMemoryKeyValueStore();
      final first = containerWith(store);
      first.read(favoritesProvider.notifier)
        ..toggle('r101')
        ..toggle('r202')
        ..toggle('r101'); // off again
      await Future<void>.delayed(Duration.zero);

      final second = containerWith(store);
      expect(second.read(favoritesProvider), {'r202'});
    });
  });

  group('recents persistence', () {
    test('record, cap order, clear', () async {
      final store = InMemoryKeyValueStore();
      final first = containerWith(store);
      final notifier = first.read(recentPicksProvider.notifier)
        ..record((id: 'a', name: 'A', subtitle: 's'))
        ..record((id: 'b', name: 'B', subtitle: 's'))
        ..record((id: 'a', name: 'A', subtitle: 's')); // dedupe to front
      await Future<void>.delayed(Duration.zero);
      expect(
        first.read(recentPicksProvider).map((p) => p.id).toList(),
        ['a', 'b'],
      );

      final second = containerWith(store);
      expect(
        second.read(recentPicksProvider).map((p) => p.id).toList(),
        ['a', 'b'],
      );

      notifier.clear();
      await Future<void>.delayed(Duration.zero);
      final third = containerWith(store);
      expect(third.read(recentPicksProvider), isEmpty);
    });
  });
}
