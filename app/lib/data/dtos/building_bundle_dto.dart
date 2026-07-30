import '../../domain/entities/building_bundle.dart';
import '../../domain/entities/geometry.dart';
import '../../domain/entities/nav.dart';

/// Hand-written JSON codec for the bundle schema (docs/03-data-model.md).
/// Hand-written (not generated) deliberately: the schema is the platform's
/// public contract, so parsing must produce *specific, human-readable* errors
/// for community/admin tooling, and must never silently drop unknown fields
/// it should reject.
///
/// Throws [FormatException] with a JSON-path-ish message; the repository
/// translates that into a typed [DataFormatFailure].
final class BuildingBundleDto {
  static const supportedSchemaVersion = 1;

  static BuildingBundle fromJson(Map<String, dynamic> json) {
    final schema = _int(json, 'schemaVersion');
    if (schema != supportedSchemaVersion) {
      throw FormatException(
        'Unsupported schemaVersion $schema '
        '(this app supports $supportedSchemaVersion)',
      );
    }
    return BuildingBundle(
      schemaVersion: schema,
      buildingId: _str(json, 'buildingId'),
      buildingName: _str(json, 'buildingName'),
      version: _int(json, 'version'),
      floors: _list(json, 'floors', _floor),
      rooms: _list(json, 'rooms', _room),
      pois: _list(json, 'pois', _poi),
      nodes: _list(json, 'nodes', _node),
      edges: _list(json, 'edges', _edge),
    );
  }

  static Map<String, dynamic> toJson(BuildingBundle b) => {
        'schemaVersion': b.schemaVersion,
        'buildingId': b.buildingId,
        'buildingName': b.buildingName,
        'version': b.version,
        'floors': [
          for (final f in b.floors)
            {
              'id': f.id,
              'level': f.level,
              'name': f.name,
              'widthM': f.widthM,
              'heightM': f.heightM,
              if (f.planImagePath != null) 'planImagePath': f.planImagePath,
              if (f.sourcePxPerMetre != null)
                'sourcePxPerMetre': f.sourcePxPerMetre,
              'corridorWidthM': f.corridorWidthM,
              if (f.corridors.isNotEmpty)
                'corridors': [
                  for (final path in f.corridors)
                    [for (final p in path) [p.x, p.y]],
                ],
            },
        ],
        'rooms': [
          for (final r in b.rooms)
            {
              'id': r.id,
              'floorId': r.floorId,
              'name': r.name,
              'type': r.type.name,
              'aliases': r.aliases,
              'polygon': [
                for (final p in r.polygon) [p.x, p.y],
              ],
              'labelPoint': [r.labelPoint.x, r.labelPoint.y],
              if (r.nodeId != null) 'nodeId': r.nodeId,
              'tags': r.tags,
              'wheelchairAccessible': r.wheelchairAccessible,
            },
        ],
        'pois': [
          for (final p in b.pois)
            {
              'id': p.id,
              'floorId': p.floorId,
              'type': p.type.name,
              'point': [p.point.x, p.point.y],
              if (p.name != null) 'name': p.name,
              if (p.nodeId != null) 'nodeId': p.nodeId,
              'tags': p.tags,
            },
        ],
        'nodes': [
          for (final n in b.nodes)
            {
              'id': n.id,
              'floorId': n.floorId,
              'x': n.point.x,
              'y': n.point.y,
              'kind': n.kind.name,
            },
        ],
        'edges': [
          for (final e in b.edges)
            {
              'a': e.a,
              'b': e.b,
              'kind': e.kind.name,
              'lengthM': e.lengthM,
              'accessible': e.accessible,
              'bidirectional': e.bidirectional,
            },
        ],
      };

  // ------------------------------------------------------------- elements

  static Floor _floor(Map<String, dynamic> j) => Floor(
        id: _str(j, 'id'),
        level: _int(j, 'level'),
        name: _str(j, 'name'),
        widthM: _double(j, 'widthM'),
        heightM: _double(j, 'heightM'),
        planImagePath: j['planImagePath'] as String?,
        sourcePxPerMetre: (j['sourcePxPerMetre'] as num?)?.toDouble(),
        corridors: [
          for (final path in j['corridors'] as List<dynamic>? ?? const [])
            _points({'p': path}, 'p'),
        ],
        corridorWidthM: (j['corridorWidthM'] as num?)?.toDouble() ?? 2.5,
      );

  static Room _room(Map<String, dynamic> j) => Room(
        id: _str(j, 'id'),
        floorId: _str(j, 'floorId'),
        name: _str(j, 'name'),
        type: _enum(j, 'type', RoomType.values, RoomType.other),
        aliases: _strList(j, 'aliases'),
        polygon: _points(j, 'polygon'),
        labelPoint: _point(j, 'labelPoint'),
        nodeId: j['nodeId'] as String?,
        tags: _strMap(j, 'tags'),
        wheelchairAccessible: j['wheelchairAccessible'] as bool? ?? true,
      );

  static Poi _poi(Map<String, dynamic> j) => Poi(
        id: _str(j, 'id'),
        floorId: _str(j, 'floorId'),
        type: _enum(j, 'type', PoiType.values, PoiType.other),
        point: _point(j, 'point'),
        name: j['name'] as String?,
        nodeId: j['nodeId'] as String?,
        tags: _strMap(j, 'tags'),
      );

  static NavNode _node(Map<String, dynamic> j) => NavNode(
        id: _str(j, 'id'),
        floorId: _str(j, 'floorId'),
        point: Point2(_double(j, 'x'), _double(j, 'y')),
        kind: _enum(j, 'kind', NodeKind.values, NodeKind.corridor),
      );

  static NavEdge _edge(Map<String, dynamic> j) => NavEdge(
        a: _str(j, 'a'),
        b: _str(j, 'b'),
        kind: _enum(j, 'kind', EdgeKind.values, EdgeKind.corridor),
        lengthM: _double(j, 'lengthM'),
        accessible: j['accessible'] as bool? ?? true,
        bidirectional: j['bidirectional'] as bool? ?? true,
      );

  // -------------------------------------------------------------- helpers

  static String _str(Map<String, dynamic> j, String key) =>
      j[key] is String && (j[key] as String).isNotEmpty
          ? j[key] as String
          : (throw FormatException('Missing/invalid string "$key" in $j'));

  static int _int(Map<String, dynamic> j, String key) => j[key] is int
      ? j[key] as int
      : (throw FormatException('Missing/invalid int "$key" in $j'));

  static double _double(Map<String, dynamic> j, String key) =>
      j[key] is num
          ? (j[key] as num).toDouble()
          : (throw FormatException('Missing/invalid number "$key" in $j'));

  static List<T> _list<T>(
    Map<String, dynamic> j,
    String key,
    T Function(Map<String, dynamic>) parse,
  ) {
    final raw = j[key];
    if (raw == null) return const [];
    if (raw is! List) throw FormatException('"$key" must be a list');
    return [
      for (final item in raw) parse(item as Map<String, dynamic>),
    ];
  }

  static List<String> _strList(Map<String, dynamic> j, String key) {
    final raw = j[key];
    if (raw == null) return const [];
    if (raw is! List) throw FormatException('"$key" must be a list');
    return [
      for (final v in raw)
        if (v is String) v else throw FormatException('"$key" must be strings'),
    ];
  }

  static Map<String, String> _strMap(Map<String, dynamic> j, String key) {
    final raw = j[key];
    if (raw == null) return const {};
    if (raw is! Map) throw FormatException('"$key" must be an object');
    return {
      for (final e in raw.entries)
        '${e.key}': e.value is String
            ? e.value as String
            // Numbers/bools in tags are common in hand-authored data;
            // coerce rather than reject the whole building for it.
            : '${e.value}',
    };
  }

  static Point2 _point(Map<String, dynamic> j, String key) =>
      _coord(j[key], key);

  static List<Point2> _points(Map<String, dynamic> j, String key) {
    final raw = j[key];
    if (raw == null) return const [];
    if (raw is! List) throw FormatException('"$key" must be a list of [x, y]');
    return [for (final p in raw) _coord(p, key)];
  }

  /// Every coordinate goes through one validated path. Without this, a
  /// malformed point (`[1]`, `"x"`, `null`) throws RangeError/TypeError —
  /// which are Errors, not Exceptions, so they escape the repository's
  /// translation layer and crash the app instead of reporting bad data.
  static Point2 _coord(Object? raw, String key) {
    if (raw is! List || raw.length != 2 || raw[0] is! num || raw[1] is! num) {
      throw FormatException('"$key" must be [x, y] numbers, got: $raw');
    }
    return Point2((raw[0] as num).toDouble(), (raw[1] as num).toDouble());
  }

  /// Unknown enum values map to a caller-chosen fallback instead of throwing:
  /// old app versions must tolerate new kinds added by newer map data.
  static T _enum<T extends Enum>(
    Map<String, dynamic> j,
    String key,
    List<T> values,
    T fallback,
  ) {
    final raw = j[key] as String?;
    return values.firstWhere((v) => v.name == raw, orElse: () => fallback);
  }
}
