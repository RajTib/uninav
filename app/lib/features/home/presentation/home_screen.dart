import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../domain/entities/campus.dart';
import '../../feedback/presentation/report_problem_sheet.dart';
import '../../settings/presentation/settings_providers.dart';

/// Campus overview: search entry point, favorites, and every building the
/// campus has — including the ones nobody has mapped yet.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campusAsync = ref.watch(campusProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(campusAsync.valueOrNull?.name ?? 'UniNav'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            // A launcher, not a field: tapping opens the search screen, which
            // owns input, debounce, recents and result actions. Rendering a
            // real text field here would let users type into a dead input.
            child: Semantics(
              button: true,
              label: 'Search rooms, labs and offices',
              child: InkWell(
                onTap: () => context.push('/search'),
                borderRadius: BorderRadius.circular(28),
                child: Ink(
                  height: 52,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      Icon(
                        Icons.search,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Search rooms, labs, offices…',
                        style:
                            Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const _FavoritesRow(),
          Expanded(
            child: campusAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not load campus data.\n$e',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              data: (campus) => _BuildingList(campus: campus),
            ),
          ),
        ],
      ),
    );
  }
}

class _BuildingList extends ConsumerWidget {
  const _BuildingList({required this.campus});
  final Campus campus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Navigable buildings first — an unmapped block should never sit between
    // two usable ones and look broken.
    final navigable = campus.buildings.where((b) => b.isNavigable).toList();
    final planned = campus.buildings.where((b) => !b.isNavigable).toList();

    return ListView(
      children: [
        if (navigable.isNotEmpty) ...[
          const _SectionHeader('Mapped buildings'),
          for (final building in navigable)
            _BuildingTile(building: building, navigable: true),
        ],
        if (planned.isNotEmpty) ...[
          const _SectionHeader('Not mapped yet'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'These blocks exist but nobody has mapped them. '
              'Mapping is community work — every block starts here.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          for (final building in planned)
            _BuildingTile(building: building, navigable: false),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _BuildingTile extends ConsumerWidget {
  const _BuildingTile({required this.building, required this.navigable});

  final BuildingSummary building;
  final bool navigable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inProgress = building.status == BuildingStatus.inProgress;
    return ListTile(
      leading: Icon(
        navigable ? Icons.apartment : Icons.domain_disabled,
        color: navigable
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline,
      ),
      title: Text(building.displayName),
      subtitle: Text(
        [
          if (inProgress) 'Mapping in progress — some areas may be missing',
          if (building.note != null) building.note!,
        ].join(' · '),
      ),
      trailing: navigable
          ? const Icon(Icons.chevron_right)
          : TextButton(
              onPressed: () => showReportProblemSheet(
                context,
                targetLabel: building.displayName,
              ),
              child: const Text('Help map'),
            ),
      enabled: navigable,
      onTap: navigable
          ? () {
              ref
                  .read(selectedBuildingIdProvider.notifier)
                  .select(building.id);
              context.push('/map');
            }
          : null,
    );
  }
}

/// Horizontal chips for favorited rooms — one tap to the map. Hidden while
/// empty so new users see zero clutter.
class _FavoritesRow extends ConsumerWidget {
  const _FavoritesRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
    final bundle = ref.watch(bundleProvider).valueOrNull;
    if (favorites.isEmpty || bundle == null) return const SizedBox.shrink();
    final rooms = [
      for (final id in favorites)
        if (bundle.roomById(id) case final room?) room,
    ];
    if (rooms.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final room in rooms)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ActionChip(
                avatar: const Icon(Icons.star, size: 18),
                label: Text(room.name),
                onPressed: () => context.push('/map?room=${room.id}'),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      );
}
