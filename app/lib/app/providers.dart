import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/error/failure.dart';
import '../data/repositories/asset_building_repository.dart';
import '../domain/entities/building_bundle.dart';
import '../domain/entities/campus.dart';
import '../domain/repositories/building_repository.dart';
import '../domain/services/routing/astar_router.dart';
import '../domain/services/routing/nav_graph.dart';

/// Riverpod IS the DI container (docs/02-architecture.md §4): tests and the
/// future Firebase build override these providers — nothing else changes.

final buildingRepositoryProvider = Provider<BuildingRepository>(
  (ref) => AssetBuildingRepository(loader: rootBundle.loadString),
);

final routerEngineProvider = Provider<AStarRouter>((ref) => const AStarRouter());

final campusProvider = FutureProvider<Campus>((ref) async {
  final result = await ref.watch(buildingRepositoryProvider).getCampus();
  return result.fold(
    (campus) => campus,
    (failure) => throw _FailureException(failure),
  );
});

/// Which building the map, search and planner currently operate on.
/// Defaults to the first navigable building in the campus.
final selectedBuildingIdProvider =
    NotifierProvider<SelectedBuildingNotifier, String?>(
        SelectedBuildingNotifier.new,);

final class SelectedBuildingNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String buildingId) => state = buildingId;
}

/// Resolves the effective building: explicit choice, else the first
/// navigable one the campus declares.
final effectiveBuildingIdProvider = FutureProvider<String>((ref) async {
  final chosen = ref.watch(selectedBuildingIdProvider);
  if (chosen != null) return chosen;
  final campus = await ref.watch(campusProvider.future);
  final navigable = campus.buildings.where((b) => b.isNavigable);
  if (navigable.isEmpty) {
    throw StateError('No navigable building in campus ${campus.id}');
  }
  return navigable.first.id;
});

/// Bundle for the currently selected building.
final bundleProvider = FutureProvider<BuildingBundle>((ref) async {
  final buildingId = await ref.watch(effectiveBuildingIdProvider.future);
  final result =
      await ref.watch(buildingRepositoryProvider).getBundle(buildingId);
  return result.fold(
    (bundle) => bundle,
    (failure) => throw _FailureException(failure),
  );
});

final navGraphProvider = FutureProvider<NavGraph>((ref) async {
  final bundle = await ref.watch(bundleProvider.future);
  return NavGraph.fromBundles([bundle]);
});

/// Adapter so FutureProvider can carry a typed Failure to AsyncValue.error.
final class _FailureException implements Exception {
  const _FailureException(this.failure);
  final Failure failure;

  @override
  String toString() => failure.message;
}
