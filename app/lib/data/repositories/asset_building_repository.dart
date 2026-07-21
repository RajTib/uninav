import 'dart:convert';

import '../../core/error/failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/building_bundle.dart';
import '../../domain/entities/campus.dart';
import '../../domain/repositories/building_repository.dart';
import '../dtos/building_bundle_dto.dart';

/// Loads raw JSON strings by logical path. In the app this wraps
/// `rootBundle.loadString`; in tests it reads fixture files. Keeping IO
/// behind one function keeps this repository trivially testable.
typedef StringLoader = Future<String> Function(String path);

/// Serves campus and building data from bundled assets, caching parsed
/// bundles in memory. The Firebase implementation (M5) will share the DTO
/// layer and this exact contract.
final class AssetBuildingRepository implements BuildingRepository {
  AssetBuildingRepository({
    required StringLoader loader,
    this.campusId = defaultCampusId,
  }) : _loader = loader;

  /// The campus shipped in the APK. Multi-campus selection arrives with M5.
  static const defaultCampusId = 'vit-vellore';

  final StringLoader _loader;
  final String campusId;
  final _bundleCache = <String, BuildingBundle>{};

  String get _campusPath => 'assets/campuses/$campusId/campus.json';
  String _bundlePath(String buildingId) =>
      'assets/campuses/$campusId/bundle_$buildingId.json';

  @override
  Future<Result<Campus, Failure>> getCampus() async {
    try {
      final json =
          jsonDecode(await _loader(_campusPath)) as Map<String, dynamic>;
      if (json['id'] != campusId) {
        return Result.err(
          DataFormatFailure(
            'campus.json at $_campusPath declares id "${json['id']}" '
            'but this repository serves "$campusId"',
          ),
        );
      }
      return Result.ok(
        Campus(
          id: json['id'] as String,
          name: json['name'] as String,
          type: CampusType.values.firstWhere(
            (t) => t.name == json['type'],
            orElse: () => CampusType.other,
          ),
          buildings: [
            for (final b in json['buildings'] as List<dynamic>)
              _buildingSummary(b as Map<String, dynamic>),
          ],
        ),
      );
      // Catch-all: malformed JSON can throw Errors (TypeError, RangeError),
      // not just Exceptions. Bad data must degrade to a typed Failure, never
      // crash the app — this is the repository's whole job as translation
      // boundary (docs/02-architecture.md §6).
    } catch (e) {
      return Result.err(DataFormatFailure('campus.json: $e'));
    }
  }

  BuildingSummary _buildingSummary(Map<String, dynamic> json) =>
      BuildingSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        code: json['code'] as String?,
        aliases: [
          for (final a in json['aliases'] as List<dynamic>? ?? const [])
            a as String,
        ],
        status: BuildingStatus.values.firstWhere(
          (s) => s.name == json['status'],
          // Unknown status is safest read as "not navigable yet": showing a
          // building we cannot route through is worse than hiding it.
          orElse: () => BuildingStatus.planned,
        ),
        note: json['note'] as String?,
      );

  @override
  Future<Result<BuildingBundle, Failure>> getBundle(String buildingId) async {
    final cached = _bundleCache[buildingId];
    if (cached != null) return Result.ok(cached);
    try {
      final json = jsonDecode(await _loader(_bundlePath(buildingId)))
          as Map<String, dynamic>;
      final bundle = BuildingBundleDto.fromJson(json);
      _bundleCache[buildingId] = bundle;
      return Result.ok(bundle);
    } on FormatException catch (e) {
      return Result.err(DataFormatFailure('bundle $buildingId: ${e.message}'));
    } catch (e) {
      // Missing asset (Exception) or malformed structure (Error) — both are
      // "this building isn't usable", never a crash.
      return Result.err(NotFoundFailure('bundle $buildingId: $e'));
    }
  }
}
