import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/presentation/settings_providers.dart';
import 'router/app_router.dart';

class UniNavApp extends ConsumerWidget {
  const UniNavApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // select(): rebuild only when the theme changes, not on every pref write.
    final themeMode =
        ref.watch(appPrefsProvider.select((p) => p.themeMode));
    return MaterialApp.router(
      title: 'UniNav',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3F51B5)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3F51B5),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: themeMode,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
