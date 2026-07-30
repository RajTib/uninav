import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// Converts hand-surveyed floor-plan JSON (nodes with pixel coordinates +
/// edges with *step-count* weights) into a UniNav building bundle.
///
///   dart run tool/survey/floorplan_to_bundle.dart \
///       assets/campuses/maps/sjt/floor_8.json
///
/// WHY THIS EXISTS
/// The survey format is what a human can actually produce: trace a floor plan
/// image, drop points, and count paces between them. The bundle format is what
/// the app needs. The gap between them is unit reconciliation, and getting it
/// wrong is subtle:
///
///   * Edge weights are STEPS (paced by the surveyor).
///   * Node coordinates are PIXELS (read off the plan image).
///
/// Those are different units. The routing engine needs both in one unit,
/// because A*'s heuristic compares a straight-line coordinate distance against
/// accumulated edge cost. Feed it pixels-vs-steps and the heuristic is
/// meaningless.
///
/// So rather than demanding the surveyor measure in metres, this tool DERIVES
/// the scale from the data itself: it fits pixels-per-step across all edges,
/// then converts coordinates into the same metric space as the weights.
/// Imperfect pacing is fine — the fit uses the median, which ignores outliers.
///
/// THE SHAPE / POINT MODEL
/// A feature is drawn as two separable things:
///
///   * a SHAPE — the polygon outline (or `bounds` rectangle) plus the semantic
///     `kind`, `displayName` and `aliases`. It says WHAT and WHERE the room is.
///   * one or more POINTS — the doorway/junction coordinates where you actually
///     walk. Points are the only things the routing graph connects.
///
/// A point links to its shape EXPLICITLY via `ref: <shapeId>` (preferred), or
/// implicitly by sharing the shape's id (back-compat with the old "one node
/// carries polygon + x,y" format). A shape may own several points — e.g. a lift
/// junction with a lift-side and a stair-side entry — which are then joined by
/// short `door` edges so the junction reads as one connected place.
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: floorplan_to_bundle.dart <floor json> '
        '[<floor json> ...] [--out <path>] [--stride <metres>]');
    exit(64);
  }

  final outPath =
      _flag(args, '--out') ?? 'assets/campuses/vit-vellore/bundle_SJT.json';
  // Average stride length. Only affects the human-readable "45 m" figure the
  // app displays — routing decisions are unchanged by it, because every edge
  // scales identically.
  final strideM = double.tryParse(_flag(args, '--stride') ?? '0.75') ?? 0.75;

  final inputs = args.where((a) => a.endsWith('.json')).toList();
  final floors = <Map<String, dynamic>>[];
  for (final path in inputs) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('No such file: $path');
      exit(66);
    }
    floors.add(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
  }

  final result = convert(floors, strideM: strideM);

  for (final w in result.warnings) {
    stdout.writeln('warning: $w');
  }
  if (result.errors.isNotEmpty) {
    stderr.writeln('\nRefusing to write — fix these first:');
    for (final e in result.errors) {
      stderr.writeln('  $e');
    }
    exit(65);
  }

  File(outPath)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(result.bundle),
    );

  stdout.writeln('\nWrote $outPath');
  stdout.writeln(result.summary);
}

String? _flag(List<String> args, String name) {
  final i = args.indexOf(name);
  return (i >= 0 && i + 1 < args.length) ? args[i + 1] : null;
}

final class ConvertResult {
  ConvertResult(this.bundle, this.warnings, this.errors, this.summary);
  final Map<String, dynamic> bundle;
  final List<String> warnings;
  final List<String> errors;
  final String summary;
}

/// Room-ish kinds become both a Room and a graph node. Purely structural
/// kinds (lifts, stairs) become graph nodes only — but a lift JUNCTION is
/// itself a walkable lobby space, so it is room-ish too and gets both.
const _roomKinds = <String, String>{
  'classroom': 'classroom',
  'lab': 'lab',
  'room': 'other',
  'office': 'office',
  'radio_station': 'other',
  'gallery': 'auditorium',
  'library': 'library',
  'cafeteria': 'cafeteria',
  'toilet_male': 'washroom',
  'toilet_female': 'washroom',
  // A lift junction is a structural node (below) AND a walkable lobby with
  // its own traced outline — it gets a Room like any other polygon shape so
  // that outline actually gets painted instead of silently dropped.
  'lift_junction': 'junction',
};

/// Kinds that should ALSO appear as POIs, so "nearest washroom" works.
const _poiKinds = <String, String>{
  'toilet_male': 'washroom',
  'toilet_female': 'washroom',
  'water_cooler': 'waterCooler',
  'printer': 'printer',
};

/// Structural kinds → the NavNode.kind the app understands.
const _nodeKinds = <String, String>{
  'lift_junction': 'junction',
  'lift': 'elevator',
  'staircase': 'stair',
  'entrance': 'entrance',
  'exit': 'exit',
};

typedef _Px = ({double x, double y});

/// One floor's instance of a stair/lift that also appears on other floors
/// under the same survey id — the two instances get joined by a vertical
/// edge once every floor doc has been processed.
typedef _Vertical = ({
  String floorId,
  String nodeId,
  int level,
  String kind,
  double x,
  double y,
});

ConvertResult convert(
  List<Map<String, dynamic>> floorDocs, {
  double strideM = 0.75,
}) {
  final warnings = <String>[];
  final errors = <String>[];

  final floors = <Map<String, dynamic>>[];
  final rooms = <Map<String, dynamic>>[];
  final pois = <Map<String, dynamic>>[];
  final nodes = <Map<String, dynamic>>[];
  final edges = <Map<String, dynamic>>[];
  // Raw survey id -> one entry per floor it appears on, for kinds that
  // physically continue between floors (lift shafts, staircases).
  final verticals = <String, List<_Vertical>>{};

  String? buildingId;
  String? buildingName;

  for (final doc in floorDocs) {
    buildingId ??= doc['building'] as String?;
    buildingName ??= doc['buildingName'] as String? ?? '${doc['building']}';
    final level = (doc['floor'] as num).toInt();
    final floorId = 'f$level';

    final rawNodes =
        (doc['nodes'] as List<dynamic>).cast<Map<String, dynamic>>();
    final rawEdges =
        (doc['edges'] as List<dynamic>).cast<Map<String, dynamic>>();

    // ---- Separate the trace into SHAPES and POINTS ----------------------
    // A shape has an outline (polygon or bounds); a point has coordinates. A
    // node can be both (the old single-node format), in which case it is its
    // own shape and its own point.
    final shapes = <String, Map<String, dynamic>>{};
    final nodeById = <String, Map<String, dynamic>>{};
    final px = <String, _Px>{};
    for (final n in rawNodes) {
      final id = n['id'] as String;
      nodeById[id] = n;
      if (n['polygon'] is List || n['bounds'] is List) shapes[id] = n;
      final x = n['x'], y = n['y'];
      if (x is num && y is num) px[id] = (x: x.toDouble(), y: y.toDouble());
    }

    // Which shape (if any) a point belongs to: explicit `ref`, else a shared
    // id (back-compat). Returns null for a standalone/loose graph point.
    String? ownerOf(String pointId) {
      final ref = nodeById[pointId]?['ref'] as String?;
      if (ref != null && shapes.containsKey(ref)) return ref;
      if (shapes.containsKey(pointId)) return pointId;
      return null;
    }

    // shapeId -> its owned point ids (trace order); plus loose points.
    final pointsOfShape = <String, List<String>>{};
    final loosePoints = <String>[];
    for (final n in rawNodes) {
      final id = n['id'] as String;
      if (!px.containsKey(id)) continue; // shapes without their own point
      final owner = ownerOf(id);
      if (owner != null) {
        (pointsOfShape[owner] ??= <String>[]).add(id);
      } else {
        loosePoints.add(id);
      }
    }

    // ---- Derive pixels-per-step from the edges themselves ---------------
    // Each edge gives one estimate: straight-line pixel distance / paced
    // steps. The MEDIAN ignores the handful of edges where pacing or a traced
    // dot is well off; a mean would let one bad edge distort the whole floor.
    final ratios = <double>[];
    for (final e in rawEdges) {
      final a = px[e['from']], b = px[e['to']];
      final w = (e['weight'] as num?)?.toDouble() ?? 0;
      if (a == null || b == null || w <= 0) continue;
      ratios.add(_dist(a, b) / w);
    }
    if (ratios.isEmpty) {
      errors.add('floor $level: no usable edges to derive a scale from — need '
          'at least one edge whose two endpoints are placed points with a '
          'weight. (Did the tracer export drop the edges?)');
      continue;
    }
    ratios.sort();
    final pxPerStep = ratios[ratios.length ~/ 2];
    final metresPerPx = strideM / pxPerStep;
    warnings.add(
      'floor $level: derived scale ${pxPerStep.toStringAsFixed(1)} px/step '
      '(${metresPerPx.toStringAsFixed(3)} m/px, stride ${strideM}m)',
    );

    double mx(double v) => double.parse((v * metresPerPx).toStringAsFixed(2));
    List<List<double>> mxPath(List<dynamic> path) => [
          for (final pt in path)
            [
              mx(((pt as List<dynamic>)[0] as num).toDouble()),
              mx((pt[1] as num).toDouble()),
            ],
        ];

    final imageInfo = doc['image'] as Map<String, dynamic>?;
    floors.add({
      'id': floorId,
      'level': level,
      'name': _floorName(level),
      'widthM': mx(((imageInfo?['width'] ?? 1000) as num).toDouble()),
      'heightM': mx(((imageInfo?['height'] ?? 1000) as num).toDouble()),
      if (imageInfo?['file'] != null) 'planImagePath': imageInfo!['file'],
      // Lets the app draw an authoring grid labelled in plan-pixel
      // coordinates — the same numbers that appear in this survey file.
      'sourcePxPerMetre': double.parse((1 / metresPerPx).toStringAsFixed(3)),
      // Real corridor width. Only centrelines are traced; the renderer strokes
      // them this wide to paint the corridor as a walkable area.
      'corridorWidthM': (doc['corridorWidthM'] as num?)?.toDouble() ?? 2.5,
      // Traced corridor shapes, VISUAL ONLY. Routing still uses graph edges and
      // their paced weights — a graph edge says "A to B in 25 steps", nothing
      // about the corridor bending twice on the way.
      'corridors': [
        for (final path in (doc['corridors'] as List<dynamic>? ?? const []))
          mxPath(path as List<dynamic>),
      ],
    });

    // Resolve a survey id (point OR shape) to the graph node id an edge should
    // attach to: the point itself, else the shape's primary/synthetic point.
    String? synthIdOf(String shapeId) =>
        (pointsOfShape[shapeId]?.isNotEmpty ?? false)
            ? pointsOfShape[shapeId]!.first
            : '${shapeId}__c';
    String? graphNodeId(String surveyId) {
      if (px.containsKey(surveyId)) return 'n_${floorId}_$surveyId';
      if (shapes.containsKey(surveyId)) {
        return 'n_${floorId}_${synthIdOf(surveyId)}';
      }
      return null;
    }

    // ---- Emit one graph node per POINT ----------------------------------
    // A point's kind comes from its owning shape (the shape carries the
    // semantics — "this is a lift"); a loose point uses its own kind, else it
    // is a plain junction.
    //
    // Node ids are scoped by floor: two floors surveyed independently may
    // reuse the same short id (e.g. every floor's lift is called "L1"), and
    // without the floor prefix those would collide into one node instead of
    // staying distinct. Lift/staircase ids that repeat across floors are
    // instead joined explicitly below, by a vertical edge — matching the
    // "same name on every floor it serves" convention from the mapping guide.
    void addNode(String pointId, _Px p, String? kindSource) {
      final nodeId = 'n_${floorId}_$pointId';
      nodes.add({
        'id': nodeId,
        'floorId': floorId,
        'x': mx(p.x),
        'y': mx(p.y),
        'kind': _nodeKinds[kindSource] ?? 'room',
      });
      if (kindSource == 'lift' || kindSource == 'staircase') {
        (verticals[pointId] ??= []).add((
          floorId: floorId,
          nodeId: nodeId,
          level: level,
          kind: kindSource!,
          x: mx(p.x),
          y: mx(p.y),
        ));
      }
    }

    for (final id in pointsOfShape.keys
        .expand((s) => pointsOfShape[s]!)
        .followedBy(loosePoints)) {
      final owner = ownerOf(id);
      final kindSource = owner != null
          ? shapes[owner]!['kind'] as String?
          : nodeById[id]!['kind'] as String?;
      addNode(id, px[id]!, kindSource);
    }

    // ---- Rooms, POIs and per-shape structure ----------------------------
    for (final entry in shapes.entries) {
      final shapeId = entry.key;
      final s = entry.value;
      final kind = s['kind'] as String? ?? 'room';
      final pts = pointsOfShape[shapeId] ?? const <String>[];

      // A shape with no traced doorway still needs a graph node so it can be
      // routed to; synthesise one at the polygon centroid.
      final String primaryPointId;
      if (pts.isEmpty) {
        final centroidPx = _centroidPx(s, px[shapeId]);
        if (centroidPx == null) {
          errors.add('floor $level: shape "$shapeId" has neither a point nor a '
              'usable outline to place a node');
          continue;
        }
        primaryPointId = synthIdOf(shapeId)!;
        addNode(primaryPointId, centroidPx, kind);
      } else {
        primaryPointId = pts.first;
      }
      final primaryPx = px[primaryPointId] ??
          _centroidPx(s, px[shapeId])!; // synth centroid path

      // Join a shape's multiple doorways so the place is internally connected
      // (a lift junction's lift-side and stair-side points, say).
      for (var i = 1; i < pts.length; i++) {
        final a = px[pts.first]!, b = px[pts[i]]!;
        edges.add({
          'a': 'n_${floorId}_${pts.first}',
          'b': 'n_${floorId}_${pts[i]}',
          'kind': 'door',
          'lengthM':
              double.parse((_dist(a, b) * metresPerPx).toStringAsFixed(2)),
          'accessible': true,
          'bidirectional': true,
        });
      }

      final roomType = _roomKinds[kind];
      if (roomType != null) {
        final polygon = s['polygon'] is List
            ? [
                for (final pt in s['polygon'] as List<dynamic>)
                  [
                    mx(((pt as List<dynamic>)[0] as num).toDouble()),
                    mx((pt[1] as num).toDouble()),
                  ],
              ]
            : _rectPolygon(s['bounds'], mx);
        // Label sits in the middle of the room; the node sits at the doorway.
        final labelPoint = polygon.isEmpty
            ? [mx(primaryPx.x), mx(primaryPx.y)]
            : [
                polygon.map((pt) => pt[0]).reduce((a, b) => a + b) /
                    polygon.length,
                polygon.map((pt) => pt[1]).reduce((a, b) => a + b) /
                    polygon.length,
              ];
        rooms.add({
          'id': shapeId,
          'floorId': floorId,
          'name': s['displayName'] ?? shapeId,
          'type': roomType,
          'aliases': (s['aliases'] as List<dynamic>? ?? const []),
          'polygon': polygon,
          'labelPoint': labelPoint,
          'nodeId': 'n_${floorId}_$primaryPointId',
          'tags': <String, String>{},
          'wheelchairAccessible': true,
        });
      } else if (!_nodeKinds.containsKey(kind) &&
          !_poiKinds.containsKey(kind)) {
        warnings.add('unknown kind "$kind" on shape "$shapeId"; '
            'treated as a plain node');
      }

      final poiType = _poiKinds[kind];
      if (poiType != null) {
        pois.add({
          'id': 'poi_$shapeId',
          'floorId': floorId,
          'type': poiType,
          'point': [mx(primaryPx.x), mx(primaryPx.y)],
          'name': s['displayName'],
          'nodeId': 'n_${floorId}_$primaryPointId',
          'tags': {
            if (kind == 'toilet_male') 'gender': 'male',
            if (kind == 'toilet_female') 'gender': 'female',
          },
        });
      }
    }

    // ---- Loose points that are themselves rooms/POIs (old flat format) ---
    // A loose point carrying a room/poi kind has no separate shape, so handle
    // it directly (it renders as a pin, no outline).
    for (final id in loosePoints) {
      final kind = nodeById[id]!['kind'] as String? ?? 'room';
      final p = px[id]!;
      if (_roomKinds[kind] != null && !shapes.containsKey(id)) {
        rooms.add({
          'id': id,
          'floorId': floorId,
          'name': nodeById[id]!['displayName'] ?? id,
          'type': _roomKinds[kind],
          'aliases': (nodeById[id]!['aliases'] as List<dynamic>? ?? const []),
          'polygon': <List<double>>[],
          'labelPoint': [mx(p.x), mx(p.y)],
          'nodeId': 'n_${floorId}_$id',
          'tags': <String, String>{},
          'wheelchairAccessible': true,
        });
      }
      if (_poiKinds[kind] != null) {
        pois.add({
          'id': 'poi_$id',
          'floorId': floorId,
          'type': _poiKinds[kind],
          'point': [mx(p.x), mx(p.y)],
          'name': nodeById[id]!['displayName'],
          'nodeId': 'n_${floorId}_$id',
          'tags': {
            if (kind == 'toilet_male') 'gender': 'male',
            if (kind == 'toilet_female') 'gender': 'female',
          },
        });
      }
    }

    // ---- Edges from the survey ------------------------------------------
    for (final e in rawEdges) {
      final from = graphNodeId(e['from'] as String);
      final to = graphNodeId(e['to'] as String);
      final a = px[e['from']] ?? _resolvePx(e['from'] as String, shapes, px);
      final b = px[e['to']] ?? _resolvePx(e['to'] as String, shapes, px);
      if (from == null || to == null || a == null || b == null) {
        errors.add('edge ${e['from']} -> ${e['to']} references a missing node');
        continue;
      }
      final steps = (e['weight'] as num).toDouble();

      // The engine requires every edge to be at least as long as the straight
      // line between its endpoints, or A*'s heuristic stops being admissible
      // and routes can come back silently suboptimal. Clamp up to the geometric
      // minimum where paced steps and traced pixels disagree.
      final paced = steps * strideM;
      final straight = _dist(a, b) * metresPerPx;
      final lengthM = math.max(paced, straight);
      if (straight > paced * 1.05) {
        warnings.add(
          'edge ${e['from']}->${e['to']}: paced ${paced.toStringAsFixed(1)}m '
          'but plan geometry says ${straight.toStringAsFixed(1)}m — using the '
          'larger. Re-check either the step count or the two dot positions.',
        );
      }

      edges.add({
        'a': from,
        'b': to,
        'kind': 'corridor',
        'lengthM': double.parse(lengthM.toStringAsFixed(2)),
        'accessible': true,
        'bidirectional': true,
      });
    }
  }

  // ---- Vertical connections between floors sharing a stair/lift id --------
  // A lift or staircase surveyed under the same id on more than one floor is
  // one physical shaft; join its per-floor nodes with a stair/elevator edge
  // rather than letting the shared id collide (see the "same name on every
  // floor it serves" rule in docs/16-mapping-guide.md).
  verticals.forEach((sharedId, instances) {
    if (instances.length < 2) {
      if (floorDocs.length > 1) {
        warnings.add('"$sharedId" appears on only one surveyed floor — it '
            'connects nothing. Use the same id on every floor it serves.');
      }
      return;
    }
    final sorted = [...instances]..sort((a, b) => a.level.compareTo(b.level));
    for (var i = 1; i < sorted.length; i++) {
      final lower = sorted[i - 1];
      final upper = sorted[i];
      final isLift = upper.kind == 'lift';
      final floorsCrossed = upper.level - lower.level;
      // Stairs run roughly 4.5 m of travel per floor; a lift shaft is the
      // vertical distance.
      final paced = floorsCrossed * (isLift ? 4.0 : 4.5);

      // Each floor was traced from its own image at its own derived scale, so
      // the "same" shaft rarely lands on identical x/y once converted to
      // metres. The engine's A* heuristic assumes every edge is at least as
      // long as the straight line between its endpoints — including the
      // vertical rise (assumedFloorHeightM in nav_graph.dart, kept in sync
      // here) — so fall back to that straight line wherever it exceeds the
      // paced estimate, exactly as horizontal corridor edges do above.
      const assumedFloorHeightM = 3.5;
      final dx = upper.x - lower.x;
      final dy = upper.y - lower.y;
      final dz = floorsCrossed * assumedFloorHeightM;
      final straight = math.sqrt(dx * dx + dy * dy + dz * dz);
      final lengthM = math.max(paced, straight);
      if (straight > paced * 1.05) {
        warnings.add(
          'vertical "$sharedId" ${lower.floorId}->${upper.floorId}: paced '
          '${paced.toStringAsFixed(1)}m but the two floors\' traced positions '
          'put it ${straight.toStringAsFixed(1)}m apart — using the larger. '
          'The two tracings may not share a common frame.',
        );
      }

      edges.add({
        'a': lower.nodeId,
        'b': upper.nodeId,
        'kind': isLift ? 'elevator' : 'stair',
        'lengthM': double.parse(lengthM.toStringAsFixed(2)),
        'accessible': isLift,
        'bidirectional': true,
      });
    }
  });

  final bundle = {
    'schemaVersion': 1,
    'buildingId': buildingId ?? 'UNKNOWN',
    'buildingName': buildingName ?? buildingId ?? 'UNKNOWN',
    'version': 1,
    'floors': floors,
    'rooms': rooms,
    'pois': pois,
    'nodes': nodes,
    'edges': edges,
  };

  final summary = '  ${floors.length} floor(s), ${rooms.length} rooms, '
      '${pois.length} POIs, ${nodes.length} nodes, ${edges.length} edges';
  return ConvertResult(bundle, warnings, errors, summary);
}

/// Pixel centroid of a shape's outline, or its own point if it has one.
_Px? _centroidPx(Map<String, dynamic> shape, _Px? ownPoint) {
  if (ownPoint != null) return ownPoint;
  final ring = shape['polygon'] is List
      ? (shape['polygon'] as List<dynamic>)
          .map((pt) => (
                x: ((pt as List<dynamic>)[0] as num).toDouble(),
                y: (pt[1] as num).toDouble(),
              ))
          .toList()
      : shape['bounds'] is List && (shape['bounds'] as List).length == 4
          ? () {
              final v =
                  (shape['bounds'] as List).map((e) => (e as num).toDouble());
              final b = v.toList();
              return [
                (x: b[0], y: b[1]),
                (x: b[2], y: b[1]),
                (x: b[2], y: b[3]),
                (x: b[0], y: b[3]),
              ];
            }()
          : const <_Px>[];
  if (ring.isEmpty) return null;
  final cx = ring.map((p) => p.x).reduce((a, b) => a + b) / ring.length;
  final cy = ring.map((p) => p.y).reduce((a, b) => a + b) / ring.length;
  return (x: cx, y: cy);
}

/// Pixel position for an edge endpoint that names a shape rather than a point.
_Px? _resolvePx(
  String surveyId,
  Map<String, Map<String, dynamic>> shapes,
  Map<String, _Px> px,
) {
  if (px.containsKey(surveyId)) return px[surveyId];
  final shape = shapes[surveyId];
  return shape == null ? null : _centroidPx(shape, null);
}

/// Converts an optional [x1, y1, x2, y2] pixel rectangle into a four-point
/// polygon in metres. Returns an empty list when no bounds were surveyed.
List<List<double>> _rectPolygon(Object? bounds, double Function(double) mx) {
  if (bounds is! List || bounds.length != 4) return const [];
  final v = bounds.map((e) => (e as num).toDouble()).toList();
  final left = math.min(v[0], v[2]);
  final right = math.max(v[0], v[2]);
  final top = math.min(v[1], v[3]);
  final bottom = math.max(v[1], v[3]);
  return [
    [mx(left), mx(top)],
    [mx(right), mx(top)],
    [mx(right), mx(bottom)],
    [mx(left), mx(bottom)],
  ];
}

double _dist(_Px a, _Px b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

String _floorName(int level) => switch (level) {
      0 => 'Ground Floor',
      1 => '1st Floor',
      2 => '2nd Floor',
      3 => '3rd Floor',
      _ => '${level}th Floor',
    };
