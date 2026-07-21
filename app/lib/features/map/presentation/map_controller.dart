import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../navigation/presentation/route_planner_controller.dart';
import 'floor_scene.dart';

/// Map view state: which floor is shown and which room is selected.
/// A Notifier (not raw StateProviders) because the two fields have a joint
/// invariant — selecting a room implies showing its floor.
final class MapViewState {
  const MapViewState({this.floorId, this.selectedRoomId});

  /// Null = "not chosen yet"; the screen resolves a default (route start
  /// floor if a route exists, else lowest level).
  final String? floorId;
  final String? selectedRoomId;

  MapViewState copyWith({String? floorId, String? Function()? selectedRoomId}) =>
      MapViewState(
        floorId: floorId ?? this.floorId,
        selectedRoomId:
            selectedRoomId != null ? selectedRoomId() : this.selectedRoomId,
      );
}

final mapViewControllerProvider =
    NotifierProvider<MapViewController, MapViewState>(MapViewController.new);

final class MapViewController extends Notifier<MapViewState> {
  @override
  MapViewState build() => const MapViewState();

  void showFloor(String floorId) {
    // Selection is per-floor context; keep it only if it survives the switch.
    state = MapViewState(floorId: floorId, selectedRoomId: null);
  }

  /// Select a room and jump to its floor in one step.
  void selectRoom({required String roomId, required String floorId}) {
    state = MapViewState(floorId: floorId, selectedRoomId: roomId);
  }

  void clearSelection() {
    state = state.copyWith(selectedRoomId: () => null);
  }

  /// Drops the user's manual floor choice so the screen re-resolves its
  /// default. Called when a new route arrives: otherwise the sticky floor
  /// from an earlier visit wins and the map opens on a floor the route
  /// doesn't even start on.
  void clearFloorOverride() {
    state = MapViewState(selectedRoomId: state.selectedRoomId);
  }
}

/// Scene for one floor of the demo building, rebuilt automatically when the
/// bundle version changes or a route is (re)planned. autoDispose: scenes for
/// floors the user left are cheap to rebuild and shouldn't pin path memory.
final floorSceneProvider =
    FutureProvider.autoDispose.family<FloorScene, String>((ref, floorId) async {
  final bundle = await ref.watch(bundleProvider.future);
  final planner = ref.watch(plannerControllerProvider);
  return FloorScene.fromBundle(
    bundle,
    floorId,
    route: switch (planner) {
      PlannerReady(:final route) => route,
      _ => null,
    },
  );
});
