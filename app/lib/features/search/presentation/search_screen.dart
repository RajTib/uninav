import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/back_or_home_button.dart';
import '../../../domain/services/search/search_index.dart';
import 'search_controller.dart';

/// Search-first navigation (docs/09-search.md): the fastest path from
/// "I need SJT 513" to a route. Debounced input, ranked results, recents on
/// the empty query.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _textController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Restore the previous query when returning from a result.
    _textController.text = ref.read(searchQueryProvider);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _textController.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) ref.read(searchQueryProvider.notifier).set(value);
    });
  }

  void _open(SearchEntry entry, {required bool directions}) {
    ref.read(recentPicksProvider.notifier).record(
          (id: entry.id, name: entry.displayName, subtitle: entry.subtitle),
        );
    if (directions) {
      context.push('/plan?dest=${entry.id}');
    } else {
      context.push('/map?room=${entry.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider);
    final query = ref.watch(searchQueryProvider);
    final indexAsync = ref.watch(searchIndexProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const BackOrHomeButton(),
        title: TextField(
          controller: _textController,
          autofocus: true,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Room, lab, office, washroom…',
            border: InputBorder.none,
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _textController.clear();
                      ref.read(searchQueryProvider.notifier).set('');
                    },
                  ),
          ),
        ),
      ),
      body: indexAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Search unavailable: $e')),
        data: (index) {
          if (query.trim().isEmpty) return const _RecentsList();
          if (results.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.search_off, size: 48),
                    const SizedBox(height: 8),
                    Text(
                      'Nothing found for "$query".\n'
                      'It may not be mapped yet.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, i) =>
                _ResultTile(result: results[i], onOpen: _open),
          );
        },
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result, required this.onOpen});

  final SearchResult result;
  final void Function(SearchEntry, {required bool directions}) onOpen;

  @override
  Widget build(BuildContext context) {
    final entry = result.entry;
    return ListTile(
      leading: Icon(
        entry.kind == SearchEntryKind.poi ? Icons.place : Icons.meeting_room,
      ),
      title: Text(entry.displayName),
      subtitle: Text(entry.subtitle),
      trailing: IconButton(
        tooltip: 'Directions',
        icon: const Icon(Icons.directions),
        onPressed:
            entry.routable ? () => onOpen(entry, directions: true) : null,
      ),
      onTap: () => onOpen(entry, directions: false),
    );
  }
}

/// Empty-query state: recent picks, or a gentle hint on first use.
class _RecentsList extends ConsumerWidget {
  const _RecentsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recents = ref.watch(recentPicksProvider);
    if (recents.isEmpty) {
      return const Center(
        child: Text('Search rooms, labs, offices, washrooms…'),
      );
    }
    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Recent'),
        ),
        for (final pick in recents)
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(pick.name),
            subtitle: Text(pick.subtitle),
            onTap: () => context.push('/map?room=${pick.id}'),
          ),
      ],
    );
  }
}
