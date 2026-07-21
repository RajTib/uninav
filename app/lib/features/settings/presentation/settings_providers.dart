import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/key_value_store.dart';
import '../../../domain/services/routing/route_prefs.dart';

/// Bound to [InMemoryKeyValueStore] by default (tests, cold fallback);
/// main() overrides with SharedPrefsStore.
final keyValueStoreProvider =
    Provider<KeyValueStore>((ref) => InMemoryKeyValueStore());

/// User preferences that shape app behavior everywhere. Persisted as one
/// JSON blob under a versioned key: schema evolution = bump key + migrate.
final class AppPrefs {
  const AppPrefs({
    this.themeMode = ThemeMode.system,
    this.defaultRouteMode = RouteMode.fastest,
  });

  factory AppPrefs.fromJson(Map<String, dynamic> json) => AppPrefs(
        themeMode: ThemeMode.values.firstWhere(
          (m) => m.name == json['themeMode'],
          orElse: () => ThemeMode.system,
        ),
        defaultRouteMode: RouteMode.values.firstWhere(
          (m) => m.name == json['defaultRouteMode'],
          orElse: () => RouteMode.fastest,
        ),
      );

  final ThemeMode themeMode;

  /// Default routing mode for new route plans. A wheelchair user sets
  /// step-free once, here, instead of per route (docs/10-accessibility.md).
  final RouteMode defaultRouteMode;

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'defaultRouteMode': defaultRouteMode.name,
      };

  AppPrefs copyWith({ThemeMode? themeMode, RouteMode? defaultRouteMode}) =>
      AppPrefs(
        themeMode: themeMode ?? this.themeMode,
        defaultRouteMode: defaultRouteMode ?? this.defaultRouteMode,
      );

  /// The RoutePrefs preset matching the stored mode.
  RoutePrefs get routePrefs => routePrefsFor(defaultRouteMode);

  static RoutePrefs routePrefsFor(RouteMode mode) => switch (mode) {
        RouteMode.fastest => RoutePrefs.fastest,
        RouteMode.accessible => RoutePrefs.accessible,
        RouteMode.preferLift => RoutePrefs.preferLift,
      };
}

final appPrefsProvider =
    NotifierProvider<AppPrefsNotifier, AppPrefs>(AppPrefsNotifier.new);

final class AppPrefsNotifier extends Notifier<AppPrefs> {
  static const _key = 'prefs.v1';

  @override
  AppPrefs build() {
    final raw = ref.watch(keyValueStoreProvider).getString(_key);
    if (raw == null) return const AppPrefs();
    try {
      return AppPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      // Catch-all on purpose: wrong-shaped JSON throws TypeError (an Error,
      // not Exception). Corrupt prefs must never brick the app.
    } catch (_) {
      return const AppPrefs();
    }
  }

  void setThemeMode(ThemeMode mode) =>
      _update(state.copyWith(themeMode: mode));

  void setDefaultRouteMode(RouteMode mode) =>
      _update(state.copyWith(defaultRouteMode: mode));

  void _update(AppPrefs next) {
    state = next;
    // Fire-and-forget: prefs writes must never block or crash the UI.
    ref
        .read(keyValueStoreProvider)
        .setString(_key, jsonEncode(next.toJson()))
        .ignore();
  }
}

/// Favorite rooms (ids). Persisted; boosts search, surfaces on home.
final favoritesProvider =
    NotifierProvider<FavoritesNotifier, Set<String>>(FavoritesNotifier.new);

final class FavoritesNotifier extends Notifier<Set<String>> {
  static const _key = 'favorites.v1';

  @override
  Set<String> build() {
    final raw = ref.watch(keyValueStoreProvider).getString(_key);
    if (raw == null) return const {};
    try {
      return {
        for (final id in jsonDecode(raw) as List<dynamic>) id as String,
      };
    } catch (_) {
      return const {};
    }
  }

  void toggle(String roomId) {
    final next = {...state};
    next.contains(roomId) ? next.remove(roomId) : next.add(roomId);
    state = next;
    ref
        .read(keyValueStoreProvider)
        .setString(_key, jsonEncode(next.toList()))
        .ignore();
  }
}
