import 'package:flutter/material.dart';

/// Shows a simple single-field dialog and returns the trimmed text,
/// or null if the user cancelled.
Future<String?> showAddItemDialog(BuildContext context, String title) async {
  final controller = TextEditingController();
  String? result;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (_) {
          final text = controller.text.trim();
          if (text.isNotEmpty) {
            result = text;
            Navigator.of(ctx).pop();
          }
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final text = controller.text.trim();
            if (text.isNotEmpty) {
              result = text;
              Navigator.of(ctx).pop();
            }
          },
          child: const Text('Add'),
        ),
      ],
    ),
  );
  // Defer dispose until after the exit animation releases the listener.
  WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  return result;
}
