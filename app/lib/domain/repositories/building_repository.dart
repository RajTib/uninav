import '../../core/error/failure.dart';
import '../../core/result/result.dart';
import '../entities/building_bundle.dart';
import '../entities/campus.dart';

/// Domain contract for map data. Implementations: bundled assets (M1),
/// Firebase Storage + disk cache (M5). The domain never knows which.
abstract interface class BuildingRepository {
  /// The campus this repository serves. An instance is bound to one campus —
  /// the id is deliberately NOT a parameter here, because it was previously
  /// duplicated between the implementation's configuration and every call
  /// site, and the two could silently disagree. Multi-campus support means
  /// constructing a repository per campus (via a provider family), not
  /// threading an id through every method.
  Future<Result<Campus, Failure>> getCampus();

  /// Loads (and caches) the full bundle for one building.
  Future<Result<BuildingBundle, Failure>> getBundle(String buildingId);
}
