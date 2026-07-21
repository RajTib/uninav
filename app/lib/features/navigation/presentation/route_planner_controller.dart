import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/error/failure.dart';
import '../../../domain/services/routing/route.dart';
import '../../../domain/services/routing/route_prefs.dart';

/// Explicit state machine for route planning (docs/02-architecture.md §4):
/// sealed states force the UI to handle every outcome, including the
/// user-meaningful difference between "disconnected" and "no accessible way".
sealed class PlannerState {
  const PlannerState();
}

final class PlannerIdle extends PlannerState {
  const PlannerIdle();
}

final class PlannerComputing extends PlannerState {
  const PlannerComputing();
}

final class PlannerReady extends PlannerState {
  const PlannerReady(this.route);
  final NavRoute route;
}

final class PlannerNoPath extends PlannerState {
  const PlannerNoPath(this.reason);
  final RoutingFailureReason reason;
}

final class PlannerError extends PlannerState {
  const PlannerError(this.message);
  final String message;
}

final plannerControllerProvider =
    NotifierProvider<PlannerController, PlannerState>(PlannerController.new);

final class PlannerController extends Notifier<PlannerState> {
  @override
  PlannerState build() => const PlannerIdle();

  Future<void> plan({
    required String fromNodeId,
    required String toNodeId,
    required RoutePrefs prefs,
  }) async {
    state = const PlannerComputing();
    try {
      final graph = await ref.read(navGraphProvider.future);
      // Graph is small in M1; move findRoute into compute() when bundles
      // exceed ~3k nodes (docs/11-performance.md).
      final result = ref.read(routerEngineProvider).findRoute(
            graph,
            from: fromNodeId,
            to: toNodeId,
            prefs: prefs,
          );
      state = result.fold(
        PlannerReady.new,
        (f) => PlannerNoPath(f.reason),
      );
    } on Exception catch (e) {
      state = PlannerError(e.toString());
    }
  }

  /// "Nearest X" (docs/04 §3): route to the closest of [goalNodeIds].
  Future<void> planNearest({
    required String fromNodeId,
    required Set<String> goalNodeIds,
    required RoutePrefs prefs,
  }) async {
    state = const PlannerComputing();
    try {
      final graph = await ref.read(navGraphProvider.future);
      final result = ref.read(routerEngineProvider).findNearestRoute(
            graph,
            from: fromNodeId,
            goals: goalNodeIds,
            prefs: prefs,
          );
      state = result.fold(
        PlannerReady.new,
        (f) => PlannerNoPath(f.reason),
      );
    } on Exception catch (e) {
      state = PlannerError(e.toString());
    }
  }

  void reset() => state = const PlannerIdle();
}
