import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'data/sources/shared_prefs_store.dart';
import 'features/settings/presentation/settings_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Resolve the prefs plugin once here so all later reads are synchronous.
  // Tests skip main() entirely and get the in-memory store by default.
  final sharedPrefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        keyValueStoreProvider.overrideWithValue(SharedPrefsStore(sharedPrefs)),
      ],
      child: const UniNavApp(),
    ),
  );
}
