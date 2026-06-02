import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Shows a confirmation dialog and, if confirmed, calls [onDelete].
/// Pass [popAfter] = true on detail screens that should navigate back once
/// the entry is gone.
Future<void> confirmDelete(
  BuildContext context, {
  required Future<void> Function() onDelete,
  bool popAfter = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete this entry?'),
      content: const Text("This can't be undone."),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(
            'Delete',
            style: TextStyle(color: Theme.of(ctx).colorScheme.error),
          ),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) {
    await onDelete();
    if (popAfter && context.mounted) context.pop();
  }
}
