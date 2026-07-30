import 'geometry.dart';
import 'nav.dart';

/// The canonical, versioned map unit: one building's floors, rooms, POIs and
/// navigation graph, loaded/cached/rendered as a whole.
/// Mirrors the bundle JSON schema (docs/03-data-model.md).
final class BuildingBundle {
  const BuildingBundle({
    required this.schemaVersion,
    required this.buildingId,
    required this.buildingName,
    required this.version,
    required this.floors,
    required this.rooms,
    required this.pois,
    required this.nodes,
    required this.edges,
  });

  final int schemaVersion;
  final String buildingId;
  final String buildingName;
  final int version;
  final List<Floor> floors;
  final List<Room> rooms;
  final List<Poi> pois;
  final List<NavNode> nodes;
  final List<NavEdge> edges;

  Floor? floorById(String id) =>
      floors.where((f) => f.id == id).firstOrNull;

  Room? roomById(String id) => rooms.where((r) => r.id == id).firstOrNull;

  Poi? poiById(String id) => pois.where((p) => p.id == id).firstOrNull;

  /// Resolves any destination id — room or POI — to its graph node.
  /// Callers (planner, search) treat destinations uniformly.
  String? routeNodeIdOf(String id) =>
      roomById(id)?.nodeId ?? poiById(id)?.nodeId;

  /// Human name for any destination id (room name, or POI name/type).
  String? displayNameOf(String id) {
    final room = roomById(id);
    if (room != null) return room.name;
    final poi = poiById(id);
    if (poi != null) return poi.name ?? poi.type.name;
    return null;
  }
}

final class Floor {
  const Floor({
    required this.id,
    required this.level,
    required this.name,
    required this.widthM,
    required this.heightM,
    this.planImagePath,
    this.sourcePxPerMetre,
    this.corridors = const [],
    this.corridorWidthM = 2.5,
  });

  final String id;

  /// 0 = ground; negative = basement.
  final int level;
  final String name;
  final double widthM;
  final double heightM;

  /// Optional raster underlay (docs/05-map-representation.md, hybrid option).
  final String? planImagePath;

  /// How many pixels of the ORIGINAL survey/plan image make one metre.
  /// Recorded so authoring tools can display a grid labelled in the same
  /// coordinates the surveyor edits (plan pixels), rather than in metres —
  /// otherwise "move this box left" means converting units by hand.
  /// Null for bundles not derived from a plan image.
  final double? sourcePxPerMetre;

  /// Traced corridor shapes for DRAWING only — each is a polyline in metres.
  /// Routing ignores these entirely and uses the navigation graph, because
  /// how a corridor looks and how far you walk down it are separate facts.
  /// Empty when a floor has been surveyed but not traced.
  final List<List<Point2>> corridors;

  /// How wide corridors actually are, in metres. Only the CENTRELINE is
  /// traced; stroking it at this width paints the corridor as a walkable
  /// area. That is half the clicks of outlining both walls, and corner
  /// joins come out correct automatically.
  final double corridorWidthM;
}

final class Room {
  const Room({
    required this.id,
    required this.floorId,
    required this.name,
    required this.type,
    required this.labelPoint,
    this.aliases = const [],
    this.polygon = const [],
    this.nodeId,
    this.tags = const {},
    this.wheelchairAccessible = true,
  });

  final String id;
  final String floorId;
  final String name;
  final RoomType type;
  final List<String> aliases;

  /// May be empty during early mapping (label-only room).
  final List<Point2> polygon;
  final Point2 labelPoint;

  /// Entry node into the navigation graph; null while unmapped for routing.
  final String? nodeId;
  final Map<String, String> tags;
  final bool wheelchairAccessible;
}

enum RoomType {
  classroom,
  lab,
  office,
  auditorium,
  library,
  washroom,
  cafeteria,
  utility,

  /// A lift/stair lobby: a walkable space in its own right (people stand and
  /// pass through it), not just a corridor endpoint. Structurally like a
  /// corridor — same fill style — but it is a bounded room, not a line.
  junction,
  other,
}

final class Poi {
  const Poi({
    required this.id,
    required this.floorId,
    required this.type,
    required this.point,
    this.name,
    this.nodeId,
    this.tags = const {},
  });

  final String id;
  final String floorId;
  final PoiType type;
  final Point2 point;
  final String? name;
  final String? nodeId;
  final Map<String, String> tags;
}

enum PoiType {
  washroom,
  waterCooler,
  printer,
  atm,
  vending,
  firstAid,
  entrance,
  exit,
  other,
}
