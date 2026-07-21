import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../domain/services/search/search_index.dart';
import '../../settings/presentation/settings_providers.dart';

/// Index built once per bundle version (cheap: seconds of app life vs
/// per-keystroke work). Multi-building campuses later just pass more bundles.
final searchIndexProvider = FutureProvider<SearchIndex>((ref) async {
  final bundle = await ref.watch(bundleProvider.future);
  return SearchIndex.fromBundles([bundle]);
});

/// Raw query text; the screen debounces before writing here so every
/// downstream listener sees settled input.
final searchQueryProvider =
    NotifierProvider<SearchQueryNotifier, String>(SearchQueryNotifier.new);

final class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}

/// One remembered search pick. Carries display data so the recents list
/// renders without re-resolving ids against the index.
typedef RecentPick = ({String id, String name, String subtitle});

/// Recently opened results (most recent first, capped). In-memory for now;
/// persisted + synced with user prefs in M4/M5 — the interface won't change.
final recentPicksProvider =
    NotifierProvider<RecentPicksNotifier, List<RecentPick>>(
        RecentPicksNotifier.new,);

final class RecentPicksNotifier extends Notifier<List<RecentPick>> {
  static const _cap = 8;
  static const _key = 'recents.v1';

  @override
  List<RecentPick> build() {
    final raw = ref.watch(keyValueStoreProvider).getString(_key);
    if (raw == null) return const [];
    try {
      return [
        for (final item in jsonDecode(raw) as List<dynamic>)
          (
            id: (item as Map<String, dynamic>)['id'] as String,
            name: item['name'] as String,
            subtitle: item['subtitle'] as String,
          ),
      ];
    } catch (_) {
      return const []; // corrupt cache is disposable, never fatal
    }
  }

  void record(RecentPick pick) {
    final next = [pick, ...state.where((p) => p.id != pick.id)];
    state = next.length > _cap ? next.sublist(0, _cap) : next;
    _persist();
  }

  void clear() {
    state = const [];
    ref.read(keyValueStoreProvider).remove(_key).ignore();
  }

  void _persist() {
    ref
        .read(keyValueStoreProvider)
        .setString(
          _key,
          jsonEncode([
            for (final p in state)
              {'id': p.id, 'name': p.name, 'subtitle': p.subtitle},
          ]),
        )
        .ignore();
  }
}

/// Ranked results for the current query.
final searchResultsProvider = Provider<List<SearchResult>>((ref) {
  final query = ref.watch(searchQueryProvider);
  final index = ref.watch(searchIndexProvider).valueOrNull;
  if (index == null || query.trim().isEmpty) return const [];
  return index.query(
    query,
    recentIds: {for (final p in ref.watch(recentPicksProvider)) p.id},
    favoriteIds: ref.watch(favoritesProvider),
  );
});
