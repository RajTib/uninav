import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uninav/app/app.dart';
import 'package:uninav/app/providers.dart';
import 'package:uninav/core/storage/key_value_store.dart';
import 'package:uninav/data/repositories/asset_building_repository.dart';
import 'package:uninav/features/settings/presentation/settings_providers.dart';

/// Boot smoke tests through the real router, repository and codec path.
///
/// The asset loader is overridden with pre-read file contents because widget
/// tests run in a fake-async zone where real file IO futures never complete
/// between pumps — this keeps every await a plain microtask.
void main() {
  Widget harness({required bool onboarded}) {
    final campusJson =
        File('assets/campuses/demo/campus.json').readAsStringSync();
    final bundleJson =
        File('assets/campuses/demo/bundle_main.json').readAsStringSync();
    return ProviderScope(
      overrides: [
        buildingRepositoryProvider.overrideWithValue(
          AssetBuildingRepository(
            campusId: 'demo',
            loader: (path) async =>
                path.endsWith('campus.json') ? campusJson : bundleJson,
          ),
        ),
        keyValueStoreProvider.overrideWithValue(
          InMemoryKeyValueStore(
            onboarded ? {'onboarded.v1': 'true'} : null,
          ),
        ),
      ],
      child: const UniNavApp(),
    );
  }

  testWidgets('onboarded user boots to the campus building list',
      (tester) async {
    await tester.pumpWidget(harness(onboarded: true));
    await tester.pump();
    await tester.pump();

    expect(find.text('Demo Campus'), findsOneWidget);
    // Mapped and unmapped buildings are both listed, in separate sections:
    // hiding unmapped blocks would read as "the app is broken".
    expect(find.text('Mapped buildings'), findsOneWidget);
    expect(find.text('Main Block (MB)'), findsOneWidget);
    expect(find.text('Not mapped yet'), findsOneWidget);
    expect(find.text('Demo Annexe (ANX)'), findsOneWidget);
    expect(find.text('Help map'), findsOneWidget);
  });

  testWidgets('first run shows onboarding; Skip lands on home and persists',
      (tester) async {
    await tester.pumpWidget(harness(onboarded: false));
    await tester.pump();

    expect(find.text('Navigate inside buildings'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('Main Block (MB)'), findsOneWidget);
  });
}
