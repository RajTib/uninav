import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uninav/data/dtos/building_bundle_dto.dart';
import 'package:uninav/domain/entities/nav.dart';

void main() {
  Map<String, dynamic> loadFixture() =>
      jsonDecode(
        File('assets/campuses/demo/bundle_main.json').readAsStringSync(),
      ) as Map<String, dynamic>;

  group('BuildingBundleDto', () {
    test('parses the demo fixture completely', () {
      final b = BuildingBundleDto.fromJson(loadFixture());
      expect(b.buildingId, 'main');
      expect(b.floors, hasLength(2));
      expect(b.rooms, hasLength(5));
      expect(b.pois, hasLength(1));
      expect(b.nodes, hasLength(17));
      expect(b.edges, hasLength(17));
      final lab = b.roomById('r103')!;
      expect(lab.aliases, contains('Lab 103'));
      expect(lab.tags['dept'], 'Physics');
      final stair =
          b.edges.singleWhere((e) => e.kind == EdgeKind.stair);
      expect(stair.accessible, isFalse);
    });

    test('round-trips toJson -> fromJson losslessly', () {
      final original = BuildingBundleDto.fromJson(loadFixture());
      final reparsed =
          BuildingBundleDto.fromJson(BuildingBundleDto.toJson(original));
      expect(BuildingBundleDto.toJson(reparsed),
          BuildingBundleDto.toJson(original),);
    });

    test('rejects unsupported schema versions with a clear message', () {
      final json = loadFixture()..['schemaVersion'] = 99;
      expect(
        () => BuildingBundleDto.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('schemaVersion 99'),
          ),
        ),
      );
    });

    test('rejects a room missing its id', () {
      final json = loadFixture();
      ((json['rooms'] as List<dynamic>).first as Map<String, dynamic>)
          .remove('id');
      expect(() => BuildingBundleDto.fromJson(json),
          throwsA(isA<FormatException>()),);
    });

    test('malformed coordinates raise FormatException, never an Error', () {
      // Errors (RangeError/TypeError) would escape the repository's
      // translation layer and crash the app; these must be Exceptions.
      for (final bad in <Object?>[
        [1],
        ['x', 'y'],
        'nope',
        null,
      ]) {
        final json = loadFixture();
        ((json['rooms'] as List<dynamic>).first
            as Map<String, dynamic>)['labelPoint'] = bad;
        expect(
          () => BuildingBundleDto.fromJson(json),
          throwsA(isA<FormatException>()),
          reason: 'labelPoint = $bad',
        );
      }

      final polyJson = loadFixture();
      ((polyJson['rooms'] as List<dynamic>).first
          as Map<String, dynamic>)['polygon'] = [
        [0, 0],
        [1],
      ];
      expect(
        () => BuildingBundleDto.fromJson(polyJson),
        throwsA(isA<FormatException>()),
      );
    });

    test('non-string tag values are coerced, not rejected', () {
      final json = loadFixture();
      ((json['rooms'] as List<dynamic>).first as Map<String, dynamic>)['tags'] =
          {'capacity': 60, 'exam': true};
      final bundle = BuildingBundleDto.fromJson(json);
      expect(bundle.rooms.first.tags['capacity'], '60');
      expect(bundle.rooms.first.tags['exam'], 'true');
    });

    test('unknown enum values fall back instead of crashing old clients', () {
      final json = loadFixture();
      ((json['rooms'] as List<dynamic>).first as Map<String, dynamic>)['type'] =
          'hologram_deck';
      final b = BuildingBundleDto.fromJson(json);
      expect(b.rooms.first.type.name, 'other');
    });
  });
}
