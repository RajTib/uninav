import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/error/failure.dart';
import '../../../core/widgets/back_or_home_button.dart';
import '../../../domain/entities/building_bundle.dart';
import '../../../domain/services/routing/route.dart';
import '../../../domain/services/routing/route_prefs.dart';
import '../../feedback/presentation/report_problem_sheet.dart';
import '../../settings/presentation/settings_providers.dart';
import 'route_planner_controller.dart';

/// Milestone-1 navigation proof: pick start/destination rooms and a mode,
/// get the step list. The map overlay replaces the text-only view in M2 —
/// but the step list stays forever as the primary accessibility surface
/// (docs/10-accessibility.md).
class RoutePlannerScreen extends ConsumerStatefulWidget {
  const RoutePlannerScreen({
    super.key,
    this.initialDestinationRoomId,
    this.initialFromRoomId,
  });

  final String? initialDestinationRoomId;
  final String? initialFromRoomId;

  @override
  ConsumerState<RoutePlannerScreen> createState() =>
      _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends ConsumerState<RoutePlannerScreen> {
  String? _fromRoomId;
  String? _toRoomId;
  RoutePrefs _prefs = RoutePrefs.fastest;

  @override
  void initState() {
    super.initState();
    _toRoomId = widget.initialDestinationRoomId;
    _fromRoomId = widget.initialFromRoomId;
    // Respect the user's saved default (e.g. step-free always) — the
    // accessibility promise is "set once, applies everywhere".
    _prefs = ref.read(appPrefsProvider).routePrefs;
  }

  void _plan(BuildingBundle bundle) {
    final from = bundle.routeNodeIdOf(_fromRoomId ?? '');
    final to = bundle.routeNodeIdOf(_toRoomId ?? '');
    if (from == null || to == null) return;
    ref.read(plannerControllerProvider.notifier).plan(
          fromNodeId: from,
          toNodeId: to,
          prefs: _prefs,
        );
  }

  @override
  Widget build(BuildContext context) {
    final bundleAsync = ref.watch(bundleProvider);
    final planner = ref.watch(plannerControllerProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const BackOrHomeButton(),
        title: const Text('Plan route'),
      ),
      body: bundleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(message: e.toString()),
        data: (bundle) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _RoomDropdown(
              label: 'From',
              bundle: bundle,
              value: _fromRoomId,
              onChanged: (v) => setState(() => _fromRoomId = v),
            ),
            const SizedBox(height: 12),
            _RoomDropdown(
              label: 'To',
              bundle: bundle,
              value: _toRoomId,
              onChanged: (v) => setState(() => _toRoomId = v),
            ),
            const SizedBox(height: 16),
            SegmentedButton<RoutePrefs>(
              segments: const [
                ButtonSegment(
                  value: RoutePrefs.fastest,
                  label: Text('Fastest'),
                  icon: Icon(Icons.directions_walk),
                ),
                ButtonSegment(
                  value: RoutePrefs.accessible,
                  label: Text('Step-free'),
                  icon: Icon(Icons.accessible),
                ),
                ButtonSegment(
                  value: RoutePrefs.preferLift,
                  label: Text('Prefer lift'),
                  icon: Icon(Icons.elevator),
                ),
              ],
              selected: {_prefs},
              onSelectionChanged: (s) => setState(() => _prefs = s.first),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: (_fromRoomId != null && _toRoomId != null)
                  ? () => _plan(bundle)
                  : null,
              icon: const Icon(Icons.route),
              label: const Text('Find route'),
            ),
            const SizedBox(height: 24),
            _PlannerResult(state: planner, bundle: bundle),
          ],
        ),
      ),
    );
  }
}

class _RoomDropdown extends StatelessWidget {
  const _RoomDropdown({
    required this.label,
    required this.bundle,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final BuildingBundle bundle;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final rooms = bundle.rooms.where((r) => r.nodeId != null);
    final pois = bundle.pois.where((p) => p.nodeId != null);
    return DropdownButtonFormField<String>(
      key: ValueKey(label),
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final room in rooms)
          DropdownMenuItem(
            value: room.id,
            child: Text(
              '${room.name} · ${bundle.floorById(room.floorId)?.name ?? ''}',
            ),
          ),
        for (final poi in pois)
          DropdownMenuItem(
            value: poi.id,
            child: Text(
              '${poi.name ?? poi.type.name} · '
              '${bundle.floorById(poi.floorId)?.name ?? ''}',
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _PlannerResult extends StatelessWidget {
  const _PlannerResult({required this.state, required this.bundle});

  final PlannerState state;
  final BuildingBundle bundle;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      PlannerIdle() => const SizedBox.shrink(),
      PlannerComputing() =>
        const Center(child: CircularProgressIndicator()),
      PlannerError(:final message) => _ErrorView(message: message),
      PlannerNoPath(:final reason) => Card(
          child: ListTile(
            leading: const Icon(Icons.block),
            title: Text(switch (reason) {
              RoutingFailureReason.noPathForConstraints =>
                'No step-free route exists between these rooms.',
              RoutingFailureReason.disconnected =>
                'These rooms are not connected on the map yet.',
              RoutingFailureReason.nodeMissing =>
                'One of these rooms is not routable yet.',
            },),
            subtitle: const Text('Something wrong? Report it to help fix '
                'the map.'),
            trailing: TextButton(
              onPressed: () => showReportProblemSheet(context),
              child: const Text('Report'),
            ),
          ),
        ),
      PlannerReady(:final route) => _RouteView(route: route, bundle: bundle),
    };
  }
}

class _RouteView extends StatelessWidget {
  const _RouteView({required this.route, required this.bundle});

  final NavRoute route;
  final BuildingBundle bundle;

  @override
  Widget build(BuildContext context) {
    final mins = (route.estSeconds / 60).ceil();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${route.totalLengthM.round()} m · ~$mins min · '
              '${route.transitions.length} floor change'
              '${route.transitions.length == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () => context.push('/map'),
              icon: const Icon(Icons.map),
              label: const Text('View on map'),
            ),
            const Divider(),
            for (final step in route.instructions)
              ListTile(
                dense: true,
                leading: Icon(switch (step.kind) {
                  InstructionKind.start => Icons.trip_origin,
                  InstructionKind.walk => Icons.directions_walk,
                  InstructionKind.turnLeft => Icons.turn_left,
                  InstructionKind.turnRight => Icons.turn_right,
                  InstructionKind.floorChange => Icons.swap_vert,
                  InstructionKind.arrive => Icons.place,
                },),
                title: Text(step.text),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: const Text('Something went wrong'),
          subtitle: Text(message),
        ),
      );
}
