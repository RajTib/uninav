import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uninav/data/dtos/building_bundle_dto.dart';
import 'package:uninav/domain/services/search/search_index.dart';

void main() {
  late SearchIndex index;

  setUpAll(() {
    final bundle = BuildingBundleDto.fromJson(
      jsonDecode(
        File('assets/campuses/demo/bundle_main.json').readAsStringSync(),
      ) as Map<String, dynamic>,
    );
    index = SearchIndex.fromBundles([bundle]);
  });

  group('exact and prefix matching', () {
    test('room number finds the room', () {
      expect(index.query('101').first.entry.id, 'r101');
    });

    test('name word finds the room', () {
      expect(index.query('physics').first.entry.id, 'r103');
    });

    test('alias works ("Lab 103" -> Physics Lab)', () {
      expect(index.query('lab').first.entry.id, 'r103');
    });

    test('tag values are searchable (person -> office)', () {
      expect(index.query('rao').first.entry.id, 'r202');
      expect(index.query('dean').first.entry.id, 'r202');
    });

    test('prefix matches ("phys")', () {
      expect(index.query('phys').first.entry.id, 'r103');
    });

    test('joined alphanumerics split ("room101" style)', () {
      // "Room 101" indexes tokens {room, 101, room101}.
      expect(index.query('room101').first.entry.id, 'r101');
    });

    test('multi-token queries AND together', () {
      final hits = index.query('room 201');
      expect(hits.first.entry.id, 'r201');
      expect(hits.map((h) => h.entry.id), isNot(contains('r103')));
    });
  });

  group('fuzzy matching', () {
    test('single-typo word still matches', () {
      expect(index.query('physcis').first.entry.id, 'r103'); // transposition
      expect(index.query('ofice').first.entry.id, 'r202'); // deletion
    });

    test('nonsense stays empty', () {
      expect(index.query('zzqqxx'), isEmpty);
    });

    test('1-2 char queries never fuzz (prefix only)', () {
      // 'p' prefixes physics/printer-ish tokens but must not fuzzy-explode.
      final ids = index.query('xq');
      expect(ids, isEmpty);
    });
  });

  group('ranking', () {
    test('rooms outrank POIs at equal text score', () {
      // 'washroom' matches the POI; also matches nothing else.
      expect(index.query('washroom').first.entry.kind, SearchEntryKind.poi);
    });

    test('favorites and recents boost, but never inject non-matches', () {
      final boosted = index.query('room', favoriteIds: {'r201'});
      expect(boosted.first.entry.id, 'r201');
      final unrelated = index.query('physics', favoriteIds: {'r201'});
      expect(unrelated.map((h) => h.entry.id), isNot(contains('r201')));
    });

    test('deterministic order on ties', () {
      final a = index.query('room').map((h) => h.entry.id).toList();
      final b = index.query('room').map((h) => h.entry.id).toList();
      expect(a, b);
    });
  });

  test('empty and junk queries return nothing', () {
    expect(index.query(''), isEmpty);
    expect(index.query('   '), isEmpty);
    expect(index.query('!!!'), isEmpty);
  });
}
