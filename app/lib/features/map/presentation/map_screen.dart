import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/error/failure.dart';
import '../../../core/widgets/back_or_home_button.dart';
import '../../../domain/entities/building_bundle.dart';
import '../../../domain/entities/geometry.dart';
import '../../../domain/services/routing/route.dart';
import '../../feedback/presentation/report_problem_sheet.dart';
import '../../navigation/presentation/route_planner_controller.dart';
import '../../settings/presentation/settings_providers.dart';
import 'floor_painter.dart';
import 'floor_scene.dart';
import 'map_controller.dart';

/// The floor map: pan/zoom, tap-to-select rooms, floor switching, and the
/// animated route overlay (docs/08-ui-screens.md, Map row).
///
/// A11y note: the canvas is decorative from a screen reader's perspective;
/// the textual step list on the planner screen remains the primary
/// accessible surface (docs/10-accessibility.md). The map exposes a summary
/// Semantics label and all controls are regular widgets.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key, this.focusRoomId});

  /// Deep-link support: /map?room=r101 opens with that room selected.
  final String? focusRoomId;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with SingleTickerProviderStateMixin {
  static const _canvasKey = ValueKey('map-canvas');

  final _transform = TransformationController();
  final _viewScale = ValueNotifier<double>(1);
  late final AnimationController _dashAnimation;
  bool _appliedFocus = false;

  /// Size of the InteractiveViewer's viewport, captured by the LayoutBuilder
  /// around it. Needed to compute the translation that puts a scene point at
  /// the centre of the screen — the InteractiveViewer itself is unconstrained
  /// ([InteractiveViewer.constrained] is false) so it has no useful size of
  /// its own to query.
  Size _viewportSize = Size.zero;

  /// Identifies what the camera was last auto-centered on (a room id or a
  /// route instance), so a rebuild that doesn't change the target doesn't
  /// fight the user's manual pan/zoom every frame.
  Object? _lastAutoCenterTarget;

  @override
  void initState() {
    super.initState();
    _dashAnimation =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..repeat();
    _transform.addListener(() {
      _viewScale.value = _transform.value.getMaxScaleOnAxis();
    });
  }

  @override
  void dispose() {
    _dashAnimation.dispose();
    _transform.dispose();
    _viewScale.dispose();
    super.dispose();
  }

  /// Default floor: route's start floor when a route exists, else the
  /// lowest level. Explicit user choice always wins.
  String _effectiveFloorId(
      BuildingBundle bundle, MapViewState view, PlannerState planner,) {
    if (view.floorId != null) return view.floorId!;
    if (planner case PlannerReady(:final route)) {
      return route.segments.first.floorId;
    }
    final floors = [...bundle.floors]
      ..sort((a, b) => a.level.compareTo(b.level));
    return floors.first.id;
  }

  void _applyDeepLinkFocus(BuildingBundle bundle) {
    if (_appliedFocus) return;
    _appliedFocus = true;
    final room = bundle.roomById(widget.focusRoomId ?? '');
    if (room == null) return;
    // Post-frame: provider mutation during build is forbidden.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(mapViewControllerProvider.notifier)
          .selectRoom(roomId: room.id, floorId: room.floorId);
    });
  }

  void _onTapUp(FloorScene scene, TapUpDetails details) {
    final meters = Point2(
      details.localPosition.dx / scene.pxPerMeter,
      details.localPosition.dy / scene.pxPerMeter,
    );
    final room = scene.roomAt(meters);
    if (room != null) {
      _selectRoom(room);
    } else {
      ref.read(mapViewControllerProvider.notifier).clearSelection();
    }
  }

  /// Shared by the sighted tap path ([_onTapUp]) and a screen reader's
  /// double-tap-to-activate on a room's semantics node
  /// ([FloorPainter.onRoomTap]) so both land on identical app state.
  void _selectRoom(Room room) {
    ref
        .read(mapViewControllerProvider.notifier)
        .selectRoom(roomId: room.id, floorId: room.floorId);
  }

  /// Camera auto-centering (docs/15-known-issues.md #7): the selected room
  /// takes priority (it's the most specific, most recent user action); with
  /// nothing selected, a route showing its start floor is centered instead.
  /// A room/route that's already been centered on doesn't fight a manual
  /// pan — only a *new* target re-centers.
  void _maybeAutoCenter(
    MapViewState view,
    PlannerState planner,
    FloorScene scene,
  ) {
    Offset? focus;
    Object? target;
    final selectedRoomId = view.selectedRoomId;
    if (selectedRoomId != null) {
      final sceneRoom =
          scene.rooms.where((r) => r.room.id == selectedRoomId).firstOrNull;
      if (sceneRoom != null) {
        focus = sceneRoom.labelCenter;
        target = ('room', selectedRoomId);
      }
    } else if (planner case PlannerReady(:final route)
        when scene.routeStart != null) {
      focus = scene.routeStart;
      target = ('route', route);
    }

    if (target == null || target == _lastAutoCenterTarget) {
      // Selection/route cleared: forget the target so a future re-selection
      // of the same room still triggers a re-centre.
      if (target == null) _lastAutoCenterTarget = null;
      return;
    }
    _lastAutoCenterTarget = target;
    final centerOn = focus!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _centerCameraOn(centerOn);
    });
  }

  void _centerCameraOn(Offset focusScenePoint) {
    if (_viewportSize.isEmpty) return;
    final scale = _transform.value.getMaxScaleOnAxis();
    final viewportCenter = _viewportSize.center(Offset.zero);
    _transform.value = Matrix4.identity()
      ..translateByDouble(viewportCenter.dx, viewportCenter.dy, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1)
      ..translateByDouble(-focusScenePoint.dx, -focusScenePoint.dy, 0, 1);
  }

  @override
  Widget build(BuildContext context) {
    // A newly computed route re-decides which floor to show; a stale manual
    // floor choice must not win. Post-frame because listeners fire mid-build.
    ref.listen<PlannerState>(plannerControllerProvider, (previous, next) {
      if (next is PlannerReady && previous is! PlannerReady) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(mapViewControllerProvider.notifier).clearFloorOverride();
          }
        });
      }
    });

    final bundleAsync = ref.watch(bundleProvider);
    final view = ref.watch(mapViewControllerProvider);
    final planner = ref.watch(plannerControllerProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const BackOrHomeButton(),
        title: const Text('Map'),
        actions: [
          IconButton(
            tooltip: 'Plan route',
            icon: const Icon(Icons.route),
            onPressed: () => context.push('/plan'),
          ),
        ],
      ),
      body: bundleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load map: $e')),
        data: (bundle) {
          _applyDeepLinkFocus(bundle);
          final style = MapStyle.fromScheme(Theme.of(context).colorScheme);
          final floorId = _effectiveFloorId(bundle, view, planner);
          final sceneAsync = ref.watch(floorSceneProvider(floorId));
          final floors = [...bundle.floors]
            ..sort((a, b) => a.level.compareTo(b.level));
          final selectedRoom = bundle.roomById(view.selectedRoomId ?? '');

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: SegmentedButton<String>(
                  segments: [
                    for (final f in floors)
                      ButtonSegment(value: f.id, label: Text(f.name)),
                  ],
                  selected: {floorId},
                  onSelectionChanged: (s) => ref
                      .read(mapViewControllerProvider.notifier)
                      .showFloor(s.first),
                ),
              ),
              if (planner case PlannerReady(:final route))
                _RouteBanner(route: route),
              Expanded(
                child: sceneAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Scene error: $e')),
                  data: (scene) {
                    _maybeAutoCenter(view, planner, scene);
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              _viewportSize = constraints.biggest;
                              return Semantics(
                                label: '${scene.floor.name} map, '
                                    '${scene.rooms.length} rooms. Use the room '
                                    'list or search to navigate.',
                                child: InteractiveViewer(
                                  transformationController: _transform,
                                  constrained: false,
                                  minScale: 0.3,
                                  maxScale: 6,
                                  boundaryMargin: const EdgeInsets.all(200),
                                  child: GestureDetector(
                                    key: _canvasKey,
                                    onTapUp: (d) => _onTapUp(scene, d),
                                    child: CustomPaint(
                                      size: scene.sizePx,
                                      painter: FloorPainter(
                                        scene: scene,
                                        style: style,
                                        selectedRoomId: view.selectedRoomId,
                                        onRoomTap: _selectRoom,
                                        viewScale: _viewScale,
                                        scaleOf: () => _viewScale.value,
                                      ),
                                      foregroundPainter: RoutePainter(
                                        scene: scene,
                                        style: style,
                                        animation: _dashAnimation,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        if (selectedRoom != null)
                          Positioned(
                            left: 12,
                            right: 12,
                            bottom: 12,
                            child:
                                _RoomCard(bundle: bundle, room: selectedRoom),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Compact route context above the map: where this floor fits in the journey.
class _RouteBanner extends StatelessWidget {
  const _RouteBanner({required this.route});

  final NavRoute route;

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      dividerColor: Colors.transparent,
      leading: const Icon(Icons.route),
      content: Text(
        'Route shown · ${route.totalLengthM.round()} m · '
        '${route.transitions.length} floor change'
        '${route.transitions.length == 1 ? '' : 's'}',
      ),
      actions: [
        TextButton(
          onPressed: () => context.push('/plan'),
          child: const Text('Steps'),
        ),
      ],
    );
  }
}

class _RoomCard extends ConsumerWidget {
  const _RoomCard({required this.bundle, required this.room});

  final BuildingBundle bundle;
  final Room room;

  /// Washroom node ids in this building; empty set disables the button.
  Set<String> _washroomNodeIds() => {
        for (final poi in bundle.pois)
          if (poi.type == PoiType.washroom && poi.nodeId != null) poi.nodeId!,
      };

  /// Plans and reports the outcome. Without this the button silently does
  /// nothing when no route exists — the worst kind of UI feedback.
  Future<void> _planNearestWashroom(
    BuildContext context,
    WidgetRef ref,
    Set<String> washrooms,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(plannerControllerProvider.notifier).planNearest(
          fromNodeId: room.nodeId!,
          goalNodeIds: washrooms,
          prefs: ref.read(appPrefsProvider).routePrefs,
        );
    final state = ref.read(plannerControllerProvider);
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (state) {
          PlannerReady(:final route) =>
            'Nearest washroom: ${route.totalLengthM.round()} m away',
          PlannerNoPath(reason: RoutingFailureReason.noPathForConstraints) =>
            'No step-free route to a washroom from here.',
          PlannerNoPath() => 'No washroom is connected to this room yet.',
          _ => 'Could not find a washroom route.',
        },),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final floor = bundle.floorById(room.floorId);
    final isFavorite = ref.watch(favoritesProvider).contains(room.id);
    final washrooms = _washroomNodeIds();
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    room.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (room.wheelchairAccessible)
                  const Tooltip(
                    message: 'Wheelchair accessible',
                    child: Icon(Icons.accessible, size: 20),
                  ),
                IconButton(
                  tooltip: isFavorite ? 'Remove favorite' : 'Add to favorites',
                  icon: Icon(isFavorite ? Icons.star : Icons.star_border),
                  onPressed: () =>
                      ref.read(favoritesProvider.notifier).toggle(room.id),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => ref
                      .read(mapViewControllerProvider.notifier)
                      .clearSelection(),
                ),
              ],
            ),
            Text(
              [
                floor?.name ?? room.floorId,
                if (room.aliases.isNotEmpty) room.aliases.join(', '),
                ...room.tags.entries.map((e) => '${e.key}: ${e.value}'),
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilledButton.tonalIcon(
                  onPressed: room.nodeId == null
                      ? null
                      : () => context.push('/plan?dest=${room.id}'),
                  icon: const Icon(Icons.directions),
                  label: const Text('Directions'),
                ),
                OutlinedButton.icon(
                  onPressed: room.nodeId == null
                      ? null
                      : () => context.push('/plan?from=${room.id}'),
                  icon: const Icon(Icons.trip_origin),
                  label: const Text('Start here'),
                ),
                OutlinedButton.icon(
                  onPressed: room.nodeId == null || washrooms.isEmpty
                      ? null
                      : () => _planNearestWashroom(context, ref, washrooms),
                  icon: const Icon(Icons.wc),
                  label: const Text('Nearest washroom'),
                ),
                TextButton.icon(
                  onPressed: () => showReportProblemSheet(
                    context,
                    targetRoomId: room.id,
                    targetLabel: room.name,
                  ),
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Report'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
