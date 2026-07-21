import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:uninav/data/dtos/building_bundle_dto.dart';
import 'package:uninav/domain/entities/building_bundle.dart';
import 'package:uninav/domain/entities/geometry.dart';
import 'package:uninav/domain/entities/nav.dart';
import 'package:uninav/domain/services/routing/nav_graph.dart';

import 'survey_parser.dart';

/// Converts a `.survey` field file into a building bundle JSON.
///
/// Usage:
///   dart run tool/survey/survey_to_bundle.dart surveys/SJT.survey \
///       [--out assets/campuses/vit-vellore/bundle_SJT.json] [--version 1]
///
/// The generator does three jobs beyond format conversion, all of which exist
/// because the input is hand-collected data from a person walking a building:
///   1. Computes every coordinate, so the surveyor never types coordinates.
///   2. Builds the graph — corridor chains, door edges, vertical links —
///      so connectivity is structural rather than hand-maintained.
///   3. Runs the SAME validation the app runs (NavGraph.issues) and refuses
///      to write a bundle with dangling edges or unreachable rooms. Catching
///      that here, while the building is still walkable, is worth far more
///      than catching it in a bug report three weeks later.
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: survey_to_bundle.dart <survey file> '
        '[--out <path>] [--version <n>]');
    exit(64);
  }

  final inputPath = args.first;
  final outPath = _flag(args, '--out');
  final version = int.tryParse(_flag(args, '--version') ?? '1') ?? 1;

  final file = File(inputPath);
  if (!file.existsSync()) {
    stderr.writeln('No such survey file: $inputPath');
    exit(66);
  }

  final Survey survey;
  try {
    survey = parseSurvey(file.readAsStringSync());
  } on SurveyParseException catch (e) {
    stderr.writeln(e);
    exit(65);
  }

  final result = buildBundle(survey, version: version);

  for (final warning in result.warnings) {
    stdout.writeln('warning: $warning');
  }
  if (result.errors.isNotEmpty) {
    stderr.writeln('\nRefusing to write bundle — fix these first:');
    for (final error in result.errors) {
      stderr.writeln('  $error');
    }
    exit(65);
  }

  final destination = File(
    outPath ??
        'assets/campuses/vit-vellore/bundle_${survey.buildingId}.json',
  );
  destination.parent.createSync(recursive: true);
  destination.writeAsStringSync(
    const JsonEncoder.withIndent('  ')
        .convert(BuildingBundleDto.toJson(result.bundle)),
  );

  final b = result.bundle;
  stdout.writeln('\nWrote ${destination.path}');
  stdout.writeln('  ${b.floors.length} floors, ${b.rooms.length} rooms, '
      '${b.pois.length} POIs, ${b.nodes.length} nodes, ${b.edges.length} edges');
}

String? _flag(List<String> args, String name) {
  final i = args.indexOf(name);
  return (i >= 0 && i + 1 < args.length) ? args[i + 1] : null;
}

final class BuildResult {
  BuildResult(this.bundle, this.warnings, this.errors);
  final BuildingBundle bundle;
  final List<String> warnings;
  final List<String> errors;
}

/// How far a room's centre sits off the corridor centreline. Rooms are drawn
/// as simple rectangles at this offset; the admin editor (M9) will replace
/// these with traced polygons. Approximate geometry is fine — routing uses
/// the graph, not the polygons.
const _roomOffsetM = 4.0;
const _roomWidthM = 5.0;
const _roomDepthM = 6.0;

/// Vertical transports sit just off the corridor too.
const _featureOffsetM = 2.5;

BuildResult buildBundle(Survey survey, {int version = 1}) {
  final warnings = <String>[];
  final errors = <String>[];

  final floors = <Floor>[];
  final rooms = <Room>[];
  final pois = <Poi>[];
  final nodes = <NavNode>[];
  final edges = <NavEdge>[];
  final roomIds = <String>{};

  // sharedId -> list of (floorId, nodeId, level) for vertical linking.
  final verticals = <String, List<(String, String, int, AttachmentKind)>>{};

  for (final floor in survey.floors) {
    var maxX = 0.0;
    var maxY = 0.0;
    void extend(double x, double y) {
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }

    // corridorId -> distance -> nodeId, so links and shared points reuse nodes.
    final corridorNodes = <String, Map<double, String>>{};

    for (final corridor in floor.corridors) {
      if (corridor.lengthM == 0) {
        errors.add('corridor ${corridor.id} on ${floor.id} has zero length');
        continue;
      }
      extend(corridor.toX, corridor.toY);
      extend(corridor.fromX, corridor.fromY);

      final points = <double, String>{};
      corridorNodes[corridor.id] = points;

      String corridorNodeAt(double distance) {
        return points.putIfAbsent(distance, () {
          final id = 'n_${floor.id}_${corridor.id}_${_fmt(distance)}';
          final (x, y) = corridor.pointAt(distance);
          nodes.add(
            NavNode(
              id: id,
              floorId: floor.id,
              point: Point2(x, y),
              kind: NodeKind.corridor,
            ),
          );
          return id;
        });
      }

      // Always create the two ends so the corridor is a continuous chain.
      corridorNodeAt(0);
      corridorNodeAt(corridor.lengthM);

      for (final a in corridor.attachments) {
        if (a.distance < 0 || a.distance > corridor.lengthM) {
          errors.add(
            'line ${a.line}: ${a.id} at ${a.distance} m is outside '
            'corridor ${corridor.id} (0..${_fmt(corridor.lengthM)} m)',
          );
          continue;
        }
        final anchorId = corridorNodeAt(a.distance);
        final (ax, ay) = corridor.pointAt(a.distance);

        switch (a.kind) {
          case AttachmentKind.room:
            if (!roomIds.add(a.id)) {
              errors.add('line ${a.line}: duplicate room id "${a.id}"');
              continue;
            }
            final (cx, cy) =
                corridor.offsetPoint(a.distance, a.side, _roomOffsetM);
            extend(cx + _roomWidthM, cy + _roomDepthM);
            final nodeId = 'n_room_${a.id}';
            nodes.add(
              NavNode(
                id: nodeId,
                floorId: floor.id,
                point: Point2(cx, cy),
                kind: NodeKind.room,
              ),
            );
            edges.add(
              NavEdge(
                a: anchorId,
                b: nodeId,
                kind: EdgeKind.door,
                lengthM: _dist(ax, ay, cx, cy),
              ),
            );
            rooms.add(
              Room(
                id: a.id,
                floorId: floor.id,
                name: a.name ?? a.id,
                type: _roomType(a.type, a.line, warnings),
                aliases: a.aliases,
                labelPoint: Point2(cx, cy),
                polygon: _rect(cx, cy),
                nodeId: nodeId,
                tags: a.tags,
              ),
            );

          case AttachmentKind.poi:
            final (cx, cy) =
                corridor.offsetPoint(a.distance, a.side, _featureOffsetM);
            final nodeId = 'n_poi_${a.id}';
            nodes.add(
              NavNode(
                id: nodeId,
                floorId: floor.id,
                point: Point2(cx, cy),
                kind: NodeKind.corridor,
              ),
            );
            edges.add(
              NavEdge(
                a: anchorId,
                b: nodeId,
                kind: EdgeKind.corridor,
                lengthM: _dist(ax, ay, cx, cy),
              ),
            );
            pois.add(
              Poi(
                id: a.id,
                floorId: floor.id,
                type: _poiType(a.type, a.line, warnings),
                point: Point2(cx, cy),
                name: a.name,
                nodeId: nodeId,
              ),
            );

          case AttachmentKind.stair:
          case AttachmentKind.lift:
          case AttachmentKind.entrance:
            final (cx, cy) =
                corridor.offsetPoint(a.distance, a.side, _featureOffsetM);
            final nodeId = 'n_${a.id}_${floor.id}';
            nodes.add(
              NavNode(
                id: nodeId,
                floorId: floor.id,
                point: Point2(cx, cy),
                kind: switch (a.kind) {
                  AttachmentKind.stair => NodeKind.stair,
                  AttachmentKind.lift => NodeKind.elevator,
                  _ => NodeKind.entrance,
                },
              ),
            );
            edges.add(
              NavEdge(
                a: anchorId,
                b: nodeId,
                kind: EdgeKind.corridor,
                lengthM: _dist(ax, ay, cx, cy),
              ),
            );
            if (a.kind != AttachmentKind.entrance) {
              verticals
                  .putIfAbsent(a.id, () => [])
                  .add((floor.id, nodeId, floor.level, a.kind));
            }
        }
      }

      // Chain corridor nodes in distance order.
      final ordered = points.keys.toList()..sort();
      for (var i = 1; i < ordered.length; i++) {
        edges.add(
          NavEdge(
            a: points[ordered[i - 1]]!,
            b: points[ordered[i]]!,
            kind: EdgeKind.corridor,
            lengthM: ordered[i] - ordered[i - 1],
          ),
        );
      }
    }

    // Join corridors that meet.
    for (final link in floor.links) {
      final a = corridorNodes[link.corridorA]?[link.distanceA];
      final b = corridorNodes[link.corridorB]?[link.distanceB];
      if (a == null || b == null) {
        errors.add(
          'link ${link.corridorA}@${_fmt(link.distanceA)} -> '
          '${link.corridorB}@${_fmt(link.distanceB)} on ${floor.id}: '
          'no node at that distance (attach something there, or use an '
          'exact distance already used on that corridor)',
        );
        continue;
      }
      edges.add(
        NavEdge(a: a, b: b, kind: EdgeKind.corridor, lengthM: 1),
      );
    }

    floors.add(
      Floor(
        id: floor.id,
        level: floor.level,
        name: floor.name,
        widthM: maxX + 5,
        heightM: maxY + 5,
      ),
    );
  }

  // Vertical connections between floors sharing a stair/lift id.
  verticals.forEach((sharedId, instances) {
    if (instances.length < 2) {
      warnings.add(
        '"$sharedId" appears on only one floor — it connects nothing. '
        'Use the same id on every floor it serves.',
      );
      return;
    }
    instances.sort((a, b) => a.$3.compareTo(b.$3));
    for (var i = 1; i < instances.length; i++) {
      final lower = instances[i - 1];
      final upper = instances[i];
      final floorsCrossed = (upper.$3 - lower.$3).abs();
      final isLift = upper.$4 == AttachmentKind.lift;
      edges.add(
        NavEdge(
          a: lower.$2,
          b: upper.$2,
          kind: isLift ? EdgeKind.elevator : EdgeKind.stair,
          // Stairs run roughly 4.5 m of travel per floor; a lift shaft is the
          // vertical distance. Both are >= the straight-line distance, which
          // the engine requires for its heuristic to stay admissible.
          lengthM: floorsCrossed * (isLift ? 4.0 : 4.5),
          accessible: isLift,
        ),
      );
    }
  });

  final bundle = BuildingBundle(
    schemaVersion: 1,
    buildingId: survey.buildingId,
    buildingName: survey.buildingName,
    version: version,
    floors: floors,
    rooms: rooms,
    pois: pois,
    nodes: nodes,
    edges: edges,
  );

  // Same validation the app performs at runtime.
  final graph = NavGraph.fromBundles([bundle]);
  for (final issue in graph.issues) {
    switch (issue.kind) {
      case GraphIssueKind.danglingEdge:
      case GraphIssueKind.duplicateNode:
      case GraphIssueKind.impossibleLength:
        errors.add('graph: $issue');
      case GraphIssueKind.orphanNode:
        warnings.add('graph: $issue (nothing connects to it)');
    }
  }

  // Reachability: every room must be reachable from the first entrance, or
  // students will search for a room the app cannot route to.
  final entrances =
      nodes.where((n) => n.kind == NodeKind.entrance).toList();
  if (entrances.isEmpty) {
    warnings.add('no entrance declared — add one so routes have a default '
        'starting point');
  } else {
    final reachable = _reachableFrom(graph, entrances.first.id);
    for (final room in rooms) {
      if (!reachable.contains(room.nodeId)) {
        errors.add(
          'room "${room.id}" (${room.name}) is not reachable from '
          '${entrances.first.id} — check that its floor is connected by a '
          'stair or lift, and that corridors on that floor are linked',
        );
      }
    }
  }

  return BuildResult(bundle, warnings, errors);
}

Set<String> _reachableFrom(NavGraph graph, String start) {
  final seen = <String>{start};
  final queue = <String>[start];
  while (queue.isNotEmpty) {
    for (final arc in graph.arcsFrom(queue.removeLast())) {
      if (seen.add(arc.to)) queue.add(arc.to);
    }
  }
  return seen;
}

List<Point2> _rect(double cx, double cy) => [
      Point2(cx - _roomWidthM / 2, cy - _roomDepthM / 2),
      Point2(cx + _roomWidthM / 2, cy - _roomDepthM / 2),
      Point2(cx + _roomWidthM / 2, cy + _roomDepthM / 2),
      Point2(cx - _roomWidthM / 2, cy + _roomDepthM / 2),
    ];

double _dist(double ax, double ay, double bx, double by) =>
    math.sqrt(math.pow(ax - bx, 2) + math.pow(ay - by, 2));

RoomType _roomType(String? raw, int line, List<String> warnings) {
  final match = RoomType.values.where((t) => t.name == raw);
  if (match.isEmpty) {
    warnings.add('line $line: unknown room type "$raw", using "other"');
    return RoomType.other;
  }
  return match.first;
}

PoiType _poiType(String? raw, int line, List<String> warnings) {
  final match = PoiType.values.where((t) => t.name == raw);
  if (match.isEmpty) {
    warnings.add('line $line: unknown POI type "$raw", using "other"');
    return PoiType.other;
  }
  return match.first;
}

String _fmt(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
