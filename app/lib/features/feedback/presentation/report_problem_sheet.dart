import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../feedback_outbox.dart';

/// Bottom-sheet report form. This is the seed of the community pipeline:
/// zero-friction reporting is how the map finds out it's wrong
/// (docs/06-community-mapping.md).
Future<void> showReportProblemSheet(
  BuildContext context, {
  String? targetRoomId,
  String? targetLabel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _ReportForm(targetRoomId: targetRoomId, targetLabel: targetLabel),
    ),
  );
}

class _ReportForm extends ConsumerStatefulWidget {
  const _ReportForm({this.targetRoomId, this.targetLabel});

  final String? targetRoomId;
  final String? targetLabel;

  @override
  ConsumerState<_ReportForm> createState() => _ReportFormState();
}

class _ReportFormState extends ConsumerState<_ReportForm> {
  FeedbackCategory _category = FeedbackCategory.wrongLocation;
  final _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _submit() {
    ref.read(feedbackOutboxProvider.notifier).submit(
          category: _category,
          message: _message.text,
          targetRoomId: widget.targetRoomId,
        );
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Thanks! Your report is saved and will be submitted '
            'when sync is available.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.targetLabel == null
                ? 'Report a problem'
                : 'Report a problem · ${widget.targetLabel}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final category in FeedbackCategory.values)
                ChoiceChip(
                  label: Text(category.label),
                  selected: _category == category,
                  onSelected: (_) => setState(() => _category = category),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _message,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'What did you find?',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.flag),
              label: const Text('Submit report'),
            ),
          ),
        ],
      ),
    );
  }
}
