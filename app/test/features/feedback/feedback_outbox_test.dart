import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uninav/core/storage/key_value_store.dart';
import 'package:uninav/features/feedback/feedback_outbox.dart';
import 'package:uninav/features/settings/presentation/settings_providers.dart';

void main() {
  ProviderContainer containerWith(KeyValueStore store) {
    final container = ProviderContainer(
      overrides: [keyValueStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('reports queue, survive restart, and drain by id', () async {
    final store = InMemoryKeyValueStore();
    final first = containerWith(store);
    first.read(feedbackOutboxProvider.notifier)
      ..submit(
        category: FeedbackCategory.wrongLocation,
        message: 'Room 101 is actually across the corridor',
        targetRoomId: 'r101',
      )
      ..submit(
        category: FeedbackCategory.badRoute,
        message: 'Route sends me through a locked door',
      );
    await Future<void>.delayed(Duration.zero);
    expect(first.read(feedbackOutboxProvider), hasLength(2));

    // Restart: reports restored from disk.
    final second = containerWith(store);
    final restored = second.read(feedbackOutboxProvider);
    expect(restored, hasLength(2));
    expect(restored.first.targetRoomId, 'r101');
    expect(restored.first.category, FeedbackCategory.wrongLocation);

    // Sync worker drains one; the other remains.
    second
        .read(feedbackOutboxProvider.notifier)
        .markDrained({restored.first.id});
    await Future<void>.delayed(Duration.zero);
    final third = containerWith(store);
    final remaining = third.read(feedbackOutboxProvider);
    expect(remaining, hasLength(1));
    expect(remaining.single.category, FeedbackCategory.badRoute);
  });

  test('corrupt outbox JSON degrades to empty, not a crash', () {
    final c = containerWith(InMemoryKeyValueStore({
      'feedback.outbox.v1': '[{"broken": true}]',
    }),);
    expect(c.read(feedbackOutboxProvider), isEmpty);
  });
}
