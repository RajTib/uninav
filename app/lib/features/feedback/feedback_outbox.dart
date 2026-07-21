import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/presentation/settings_providers.dart';

/// A user problem report. Offline-first: reports queue locally and a sync
/// worker drains them to the `feedback` collection when Firebase lands (M5,
/// docs/03-data-model.md). The user's report always "succeeds" instantly —
/// network is our problem, not theirs.
final class FeedbackReport {
  const FeedbackReport({
    required this.id,
    required this.category,
    required this.message,
    required this.createdAtEpochMs,
    this.targetRoomId,
  });

  factory FeedbackReport.fromJson(Map<String, dynamic> json) => FeedbackReport(
        id: json['id'] as String,
        category: FeedbackCategory.values.firstWhere(
          (c) => c.name == json['category'],
          orElse: () => FeedbackCategory.other,
        ),
        message: json['message'] as String,
        createdAtEpochMs: json['createdAtEpochMs'] as int,
        targetRoomId: json['targetRoomId'] as String?,
      );

  final String id;
  final FeedbackCategory category;
  final String message;
  final int createdAtEpochMs;
  final String? targetRoomId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category.name,
        'message': message,
        'createdAtEpochMs': createdAtEpochMs,
        if (targetRoomId != null) 'targetRoomId': targetRoomId,
      };
}

enum FeedbackCategory {
  wrongLocation('Wrong location'),
  wrongName('Wrong name'),
  missingRoom('Missing room'),
  badRoute('Bad route'),
  accessibility('Accessibility issue'),
  other('Other');

  const FeedbackCategory(this.label);
  final String label;
}

final feedbackOutboxProvider =
    NotifierProvider<FeedbackOutboxNotifier, List<FeedbackReport>>(
        FeedbackOutboxNotifier.new,);

final class FeedbackOutboxNotifier extends Notifier<List<FeedbackReport>> {
  static const _key = 'feedback.outbox.v1';

  @override
  List<FeedbackReport> build() {
    final raw = ref.watch(keyValueStoreProvider).getString(_key);
    if (raw == null) return const [];
    try {
      return [
        for (final item in jsonDecode(raw) as List<dynamic>)
          FeedbackReport.fromJson(item as Map<String, dynamic>),
      ];
    } catch (_) {
      return const [];
    }
  }

  void submit({
    required FeedbackCategory category,
    required String message,
    String? targetRoomId,
  }) {
    final now = DateTime.now();
    final report = FeedbackReport(
      // Time + count is unique enough for a per-device queue.
      id: 'fb_${now.millisecondsSinceEpoch}_${state.length}',
      category: category,
      message: message.trim(),
      createdAtEpochMs: now.millisecondsSinceEpoch,
      targetRoomId: targetRoomId,
    );
    state = [...state, report];
    _persist();
  }

  /// Called by the future sync worker after successful upload.
  void markDrained(Set<String> uploadedIds) {
    state = [for (final r in state) if (!uploadedIds.contains(r.id)) r];
    _persist();
  }

  void _persist() {
    ref
        .read(keyValueStoreProvider)
        .setString(
          _key,
          jsonEncode([for (final r in state) r.toJson()]),
        )
        .ignore();
  }
}
