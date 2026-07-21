import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/back_or_home_button.dart';
import '../../../domain/services/routing/route_prefs.dart';
import '../../feedback/feedback_outbox.dart';
import '../../search/presentation/search_controller.dart';
import 'settings_providers.dart';

/// Settings: the accessibility hub and app-wide defaults
/// (docs/08-ui-screens.md). Every control writes through appPrefsProvider,
/// which persists automatically.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(appPrefsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const BackOrHomeButton(),
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          const _SectionHeader('Appearance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode),
                ),
              ],
              selected: {prefs.themeMode},
              onSelectionChanged: (s) => ref
                  .read(appPrefsProvider.notifier)
                  .setThemeMode(s.first),
            ),
          ),
          const _SectionHeader('Routing'),
          RadioListTile<RouteMode>(
            value: RouteMode.fastest,
            groupValue: prefs.defaultRouteMode,
            onChanged: (m) => _setMode(ref, m),
            title: const Text('Fastest'),
            subtitle: const Text('Shortest walk, stairs allowed'),
          ),
          RadioListTile<RouteMode>(
            value: RouteMode.accessible,
            groupValue: prefs.defaultRouteMode,
            onChanged: (m) => _setMode(ref, m),
            title: const Text('Step-free (wheelchair)'),
            subtitle: const Text(
                'Never uses stairs; reports honestly when no step-free '
                'route exists'),
          ),
          RadioListTile<RouteMode>(
            value: RouteMode.preferLift,
            groupValue: prefs.defaultRouteMode,
            onChanged: (m) => _setMode(ref, m),
            title: const Text('Prefer lift'),
            subtitle: const Text('Stairs only when much faster'),
          ),
          const _SectionHeader('Data'),
          ListTile(
            leading: const Icon(Icons.history_toggle_off),
            title: const Text('Clear recent searches'),
            onTap: () {
              ref.read(recentPicksProvider.notifier).clear();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Recent searches cleared')),
              );
            },
          ),
          const _PendingReportsTile(),
          const _SectionHeader('About'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('UniNav'),
            subtitle: Text(
                'v0.1.0 · community indoor navigation\n'
                'Map data is community-maintained; report problems from any '
                'room card.'),
          ),
        ],
      ),
    );
  }

  void _setMode(WidgetRef ref, RouteMode? mode) {
    if (mode != null) {
      ref.read(appPrefsProvider.notifier).setDefaultRouteMode(mode);
    }
  }
}

class _PendingReportsTile extends ConsumerWidget {
  const _PendingReportsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(feedbackOutboxProvider).length;
    if (count == 0) return const SizedBox.shrink();
    return ListTile(
      leading: const Icon(Icons.outbox),
      title: Text('$count queued report${count == 1 ? '' : 's'}'),
      subtitle: const Text('Will upload automatically once sync is available'),
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
