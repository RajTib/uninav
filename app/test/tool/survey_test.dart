@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:uninav/domain/entities/nav.dart';
import 'package:uninav/domain/services/routing/astar_router.dart';
import 'package:uninav/domain/services/routing/nav_graph.dart';
import 'package:uninav/domain/services/routing/route_prefs.dart';

import '../../tool/survey/survey_parser.dart';
import '../../tool/survey/survey_to_bundle.dart';

/// The survey toolchain is how every real building enters the system, so it
/// is tested like production code: a bad generator silently produces a map
/// that looks fine and routes wrongly.
void main() {
  const twoFloors = '''
building SJT "Silver Jubilee Tower" alias=SJT,Tower

floor f0 level=0 "Ground Floor"
corridor c_main from=0,20 to=60,20
entrance 0 L e_main
room 8 L SJT101 "SJT 101" classroom alias=101
room 8 R SJT102 "SJT 102" classroom alias=102
poi 15 R washroom
stair 30 R st_main
lift 34 R lift_main
room 45 L SJT103 "SJT 103" lab alias=103 tag:dept=Physics

floor f1 level=1 "First Floor"
corridor c_main from=0,20 to=60,20
stair 30 R st_main
lift 34 R lift_main
room 8 L SJT201 "SJT 201" classroom alias=201
''';

  group('corridor declaration styles', () {
    test('length + heading is equivalent to explicit endpoints', () {
      final explicit = parseSurvey('''
building B "B"
floor f0 level=0 "G"
corridor c from=0,20 to=60,20
room 8 L R1 "R1" classroom
''');
      final paced = parseSurvey('''
building B "B"
floor f0 level=0 "G"
corridor c length=60 heading=E
room 8 L R1 "R1" classroom
''');
      final a = explicit.floors.single.corridors.single;
      final b = paced.floors.single.corridors.single;
      expect(b.fromX, a.fromX);
      expect(b.fromY, a.fromY);
      expect(b.toX, a.toX);
      expect(b.toY, a.toY);
    });

    test('headings point the right way', () {
      SurveyCorridor corridorOf(String heading) => parseSurvey('''
building B "B"
floor f0 level=0 "G"
corridor c length=10 heading=$heading start=50,50
''').floors.single.corridors.single;

      expect((corridorOf('E').toX, corridorOf('E').toY), (60.0, 50.0));
      expect((corridorOf('W').toX, corridorOf('W').toY), (40.0, 50.0));
      // y grows downward, so South increases y.
      expect((corridorOf('S').toX, corridorOf('S').toY), (50.0, 60.0));
      expect((corridorOf('N').toX, corridorOf('N').toY), (50.0, 40.0));
    });

    test('a corridor with neither form is an error', () {
      expect(
        () => parseSurvey('''
building B "B"
floor f0 level=0 "G"
corridor c
'''),
        throwsA(isA<SurveyParseException>()),
      );
    });
  });

  group('parsing', () {
    test('reads building, floors, corridors and attachments', () {
      final survey = parseSurvey(twoFloors);
      expect(survey.buildingId, 'SJT');
      expect(survey.buildingName, 'Silver Jubilee Tower');
      expect(survey.aliases, ['SJT', 'Tower']);
      expect(survey.floors, hasLength(2));
      expect(survey.floors.first.corridors.single.lengthM, 60);
      // entrance, 2 rooms at 8 m, washroom POI, stair, lift, room at 45 m.
      expect(survey.floors.first.corridors.single.attachments, hasLength(7));
    });

    test('reports every bad line with its number, not just the first', () {
      expect(
        () => parseSurvey('''
building SJT "Silver Jubilee Tower"
floor f0 level=zero "Ground"
corridor c_main from=0,20 to=60,20
room notanumber L SJT101 "SJT 101" classroom
frobnicate 3
'''),
        throwsA(
          isA<SurveyParseException>().having(
            (e) => e.errors,
            'errors',
            allOf(
              hasLength(greaterThanOrEqualTo(2)),
              contains(contains('line 2')),
              contains(contains('unknown command')),
            ),
          ),
        ),
      );
    });
  });

  group('generation', () {
    test('produces a valid, fully routable bundle', () {
      final result = buildBundle(parseSurvey(twoFloors));
      expect(result.errors, isEmpty);

      final bundle = result.bundle;
      expect(bundle.buildingId, 'SJT');
      expect(bundle.floors, hasLength(2));
      expect(bundle.rooms.map((r) => r.id),
          containsAll(['SJT101', 'SJT102', 'SJT103', 'SJT201']),);
      expect(bundle.pois, hasLength(1));
      expect(bundle.roomById('SJT103')!.tags['dept'], 'Physics');
      expect(bundle.roomById('SJT101')!.aliases, ['101']);
    });

    test('places rooms on the correct side of the corridor', () {
      final bundle = buildBundle(parseSurvey(twoFloors)).bundle;
      // Corridor runs +x along y=20; in a y-down frame "left" is smaller y.
      expect(bundle.roomById('SJT101')!.labelPoint.y, lessThan(20));
      expect(bundle.roomById('SJT102')!.labelPoint.y, greaterThan(20));
      // Both sit at 8 m along the corridor.
      expect(bundle.roomById('SJT101')!.labelPoint.x, closeTo(8, 1e-9));
      expect(bundle.roomById('SJT102')!.labelPoint.x, closeTo(8, 1e-9));
    });

    test('links stairs and lifts across floors by shared id', () {
      final bundle = buildBundle(parseSurvey(twoFloors)).bundle;
      final vertical = bundle.edges.where(
        (e) => e.kind == EdgeKind.stair || e.kind == EdgeKind.elevator,
      );
      expect(vertical, hasLength(2));
      final lift = vertical.singleWhere((e) => e.kind == EdgeKind.elevator);
      expect(lift.accessible, isTrue, reason: 'lifts are step-free');
      final stair = vertical.singleWhere((e) => e.kind == EdgeKind.stair);
      expect(stair.accessible, isFalse);
    });

    test('the generated graph is clean and routes across floors', () {
      final bundle = buildBundle(parseSurvey(twoFloors)).bundle;
      final graph = NavGraph.fromBundles([bundle]);
      expect(graph.issues, isEmpty);

      final route = const AStarRouter()
          .findRoute(
            graph,
            from: bundle.roomById('SJT101')!.nodeId!,
            to: bundle.roomById('SJT201')!.nodeId!,
          )
          .fold((r) => r, (f) => fail('$f'));
      expect(route.transitions, hasLength(1));

      // Step-free routing must pick the lift over the stairs.
      final stepFree = const AStarRouter()
          .findRoute(
            graph,
            from: bundle.roomById('SJT101')!.nodeId!,
            to: bundle.roomById('SJT201')!.nodeId!,
            prefs: RoutePrefs.accessible,
          )
          .fold((r) => r, (f) => fail('$f'));
      expect(stepFree.transitions.single.kind, EdgeKind.elevator);
    });

    test('refuses a bundle whose upper floor is unreachable', () {
      // st_main only exists on f0 -> f1 is an island. This is THE mistake a
      // surveyor makes, so it must be an error, never a silent bad map.
      final result = buildBundle(parseSurvey('''
building SJT "Silver Jubilee Tower"
floor f0 level=0 "Ground"
corridor c_main from=0,20 to=60,20
entrance 0 L e_main
stair 30 R st_main
floor f1 level=1 "First"
corridor c_main from=0,20 to=60,20
room 8 L SJT201 "SJT 201" classroom
'''),);
      expect(
        result.errors.join('\n'),
        contains('SJT201'),
      );
      expect(result.errors.join('\n'), contains('not reachable'));
    });

    test('rejects an attachment beyond the end of its corridor', () {
      final result = buildBundle(parseSurvey('''
building SJT "Silver Jubilee Tower"
floor f0 level=0 "Ground"
corridor c_main from=0,20 to=60,20
entrance 0 L e_main
room 75 L SJT101 "SJT 101" classroom
'''),);
      expect(result.errors.join('\n'), contains('outside corridor'));
    });

    test('warns about a stair recorded on only one floor', () {
      final result = buildBundle(parseSurvey('''
building SJT "Silver Jubilee Tower"
floor f0 level=0 "Ground"
corridor c_main from=0,20 to=60,20
entrance 0 L e_main
stair 30 R st_lonely
room 8 L SJT101 "SJT 101" classroom
'''),);
      expect(result.warnings.join('\n'), contains('st_lonely'));
    });

    test('links two corridors on an L-shaped floor', () {
      final result = buildBundle(parseSurvey('''
building SJT "Silver Jubilee Tower"
floor f0 level=0 "Ground"
corridor c_main from=0,20 to=60,20
entrance 0 L e_main
corridor c_wing from=60,20 to=60,60
room 12 L SJT120 "SJT 120" classroom
link c_main 60 c_wing 0
'''),);
      expect(result.errors, isEmpty);
      final graph = NavGraph.fromBundles([result.bundle]);
      final route = const AStarRouter()
          .findRoute(
            graph,
            from: 'n_e_main_f0',
            to: result.bundle.roomById('SJT120')!.nodeId!,
          )
          .fold((r) => r, (f) => fail('wing unreachable: $f'));
      expect(route.totalLengthM, greaterThan(60));
    });
  });
}
