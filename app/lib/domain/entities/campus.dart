/// A venue: university, mall, hospital, airport, office. No venue-specific
/// logic anywhere in code — everything about a campus is data.
final class Campus {
  const Campus({
    required this.id,
    required this.name,
    required this.type,
    required this.buildings,
  });

  final String id;
  final String name;
  final CampusType type;

  /// Every building the venue has, mapped or not. Listing unmapped buildings
  /// is deliberate: users must be able to see that a block exists and that
  /// its map is simply missing, rather than wondering whether the app is
  /// broken — and an unmapped block is the strongest prompt to contribute.
  final List<BuildingSummary> buildings;

  Iterable<BuildingSummary> get mappedBuildings =>
      buildings.where((b) => b.status == BuildingStatus.mapped);

  BuildingSummary? buildingById(String id) =>
      buildings.where((b) => b.id == id).firstOrNull;
}

enum CampusType { university, mall, hospital, airport, office, other }

/// Lightweight building record held by the campus. The heavy geometry lives
/// in that building's own bundle, fetched only when the building is opened.
final class BuildingSummary {
  const BuildingSummary({
    required this.id,
    required this.name,
    required this.status,
    this.code,
    this.aliases = const [],
    this.note,
  });

  final String id;

  /// Full name, e.g. "Silver Jubilee Tower".
  final String name;

  /// Short campus code, e.g. "SJT" — usually how students actually refer to it.
  final String? code;
  final List<String> aliases;
  final BuildingStatus status;

  /// Optional human note, e.g. "Annexe, 2 floors".
  final String? note;

  /// What users see in a list: "Silver Jubilee Tower (SJT)".
  String get displayName => code == null ? name : '$name ($code)';

  bool get isNavigable => status != BuildingStatus.planned;
}

enum BuildingStatus {
  /// A published bundle exists; the building is navigable.
  mapped,

  /// Known to exist, no map data yet.
  planned,

  /// Mapping in progress — partially usable, shown with a caveat.
  inProgress,
}
