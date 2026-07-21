import 'dart:math' as math;

import '../../entities/building_bundle.dart';

/// In-memory search over rooms and POIs (docs/09-search.md). Pure Dart, built
/// once per bundle version, queried per keystroke. Firestore cannot do
/// substring/fuzzy search and per-keystroke server queries would be slow,
/// costly, and dead offline — at campus scale (~10^4 entries) local search
/// is faster than a network round-trip by orders of magnitude.
final class SearchIndex {
  SearchIndex._(this._entries);

  factory SearchIndex.fromBundles(List<BuildingBundle> bundles) {
    final entries = <SearchEntry>[];
    for (final bundle in bundles) {
      for (final room in bundle.rooms) {
        final texts = [room.name, ...room.aliases, ...room.tags.values];
        entries.add(
          SearchEntry(
            id: room.id,
            kind: SearchEntryKind.room,
            displayName: room.name,
            subtitle: bundle.floorById(room.floorId)?.name ?? '',
            buildingId: bundle.buildingId,
            floorId: room.floorId,
            routable: room.nodeId != null,
            tokens: {for (final t in texts) ..._tokenize(t)},
          ),
        );
      }
      for (final poi in bundle.pois) {
        final name = poi.name ?? poi.type.name;
        entries.add(
          SearchEntry(
            id: poi.id,
            kind: SearchEntryKind.poi,
            displayName: name,
            subtitle: bundle.floorById(poi.floorId)?.name ?? '',
            buildingId: bundle.buildingId,
            floorId: poi.floorId,
            routable: poi.nodeId != null,
            tokens: {..._tokenize(name), ..._tokenize(poi.type.name)},
          ),
        );
      }
    }
    return SearchIndex._(List.unmodifiable(entries));
  }

  final List<SearchEntry> _entries;

  int get entryCount => _entries.length;

  /// Ranked search. [favoriteIds]/[recentIds] boost, never filter — a
  /// favorite that doesn't match the query still doesn't appear.
  List<SearchResult> query(
    String rawQuery, {
    int limit = 20,
    Set<String> favoriteIds = const {},
    Set<String> recentIds = const {},
  }) {
    final queryTokens = _tokenize(rawQuery);
    if (queryTokens.isEmpty) return const [];

    final results = <SearchResult>[];
    for (final entry in _entries) {
      var score = 0.0;
      for (final q in queryTokens) {
        final tokenScore = _bestTokenScore(q, entry.tokens);
        if (tokenScore == 0) {
          score = 0; // every query token must match something (AND semantics)
          break;
        }
        score += tokenScore;
      }
      if (score <= 0) continue;

      score += switch (entry.kind) {
        SearchEntryKind.room => 10,
        SearchEntryKind.poi => 5,
      };
      if (favoriteIds.contains(entry.id)) score += 20;
      if (recentIds.contains(entry.id)) score += 15;
      results.add(SearchResult(entry: entry, score: score));
    }

    // Deterministic ordering: score desc, then name, then id.
    results.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byName = a.entry.displayName.compareTo(b.entry.displayName);
      return byName != 0 ? byName : a.entry.id.compareTo(b.entry.id);
    });
    return results.length > limit
        ? results.sublist(0, limit)
        : results;
  }

  /// Best match of one query token against an entry's tokens:
  /// exact 100 > prefix 80·(coverage) > fuzzy 60−10·distance.
  /// Fuzzy only runs for queries of 3+ chars — 1–2 char typos are noise.
  static double _bestTokenScore(String q, Set<String> tokens) {
    var best = 0.0;
    for (final t in tokens) {
      double s;
      if (t == q) {
        s = 100;
      } else if (t.startsWith(q)) {
        s = 80 * (q.length / t.length) + 10; // longer coverage ranks higher
      } else if (q.length >= 3) {
        final maxDist = q.length <= 5 ? 1 : 2;
        final d = _boundedEditDistance(q, t, maxDist);
        s = d < 0 ? 0 : 60.0 - 10 * d;
      } else {
        s = 0;
      }
      if (s > best) best = s;
    }
    return best;
  }

  /// Tokenizer shared by indexing and querying: lowercase, split on
  /// non-alphanumerics AND letter/digit boundaries, keep the joined form
  /// too ("SJT-513A" -> {sjt513a, sjt, 513, a}) so both "sjt513" and "513"
  /// find the room.
  static Set<String> _tokenize(String text) {
    final lower = text.toLowerCase();
    final parts = lower
        .split(RegExp(r'[^a-z0-9]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    final tokens = <String>{};
    for (final part in parts) {
      tokens.add(part);
      tokens.addAll(
        part
            .split(RegExp(r'(?<=[a-z])(?=[0-9])|(?<=[0-9])(?=[a-z])'))
            .where((p) => p.isNotEmpty),
      );
    }
    if (parts.length > 1) tokens.add(parts.join());
    return tokens;
  }

  /// Damerau-Levenshtein (optimal string alignment) with early exit when the
  /// distance must exceed [maxDist]; returns -1 in that case. Bounded so a
  /// worst-case keystroke stays trivially cheap across 10^4 entries.
  static int _boundedEditDistance(String a, String b, int maxDist) {
    if ((a.length - b.length).abs() > maxDist) return -1;
    final m = a.length, n = b.length;
    var prevPrev = List<int>.filled(n + 1, 0);
    var prev = List<int>.generate(n + 1, (j) => j);
    var curr = List<int>.filled(n + 1, 0);

    for (var i = 1; i <= m; i++) {
      curr[0] = i;
      var rowMin = curr[0];
      for (var j = 1; j <= n; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        curr[j] = math.min(
          math.min(prev[j] + 1, curr[j - 1] + 1),
          prev[j - 1] + cost,
        );
        if (i > 1 &&
            j > 1 &&
            a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
            a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
          curr[j] = math.min(curr[j], prevPrev[j - 2] + 1);
        }
        if (curr[j] < rowMin) rowMin = curr[j];
      }
      if (rowMin > maxDist) return -1; // no path back under the bound
      final tmp = prevPrev;
      prevPrev = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[n] <= maxDist ? prev[n] : -1;
  }
}

enum SearchEntryKind { room, poi }

final class SearchEntry {
  const SearchEntry({
    required this.id,
    required this.kind,
    required this.displayName,
    required this.subtitle,
    required this.buildingId,
    required this.floorId,
    required this.routable,
    required this.tokens,
  });

  final String id;
  final SearchEntryKind kind;
  final String displayName;
  final String subtitle;
  final String buildingId;
  final String floorId;
  final bool routable;
  final Set<String> tokens;
}

final class SearchResult {
  const SearchResult({required this.entry, required this.score});
  final SearchEntry entry;
  final double score;
}
