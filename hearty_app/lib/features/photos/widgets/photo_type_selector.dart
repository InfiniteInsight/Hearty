import 'package:flutter/material.dart';

import '../models/photo_type.dart';

/// Shows a modal bottom sheet that lets the user choose a [PhotoType].
///
/// Returns the selected [PhotoType], or `null` if the user cancels.
///
/// [preselected] is highlighted and has a checkmark to indicate the suggested
/// type (e.g. [PhotoType.barcode] when coming from barcode mode).
Future<PhotoType?> showPhotoTypeSelector(
  BuildContext context, {
  PhotoType? preselected,
}) async {
  return showModalBottomSheet<PhotoType>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _PhotoTypeSelectorSheet(preselected: preselected),
  );
}

class _PhotoTypeSelectorSheet extends StatelessWidget {
  final PhotoType? preselected;

  const _PhotoTypeSelectorSheet({this.preselected});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              'What did you photograph?',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
          ),
          const Divider(),
          ...PhotoType.values.map(
            (type) => _PhotoTypeTile(
              type: type,
              isPreselected: type == preselected,
              colorScheme: colorScheme,
            ),
          ),
          const Divider(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _PhotoTypeTile extends StatelessWidget {
  final PhotoType type;
  final bool isPreselected;
  final ColorScheme colorScheme;

  const _PhotoTypeTile({
    required this.type,
    required this.isPreselected,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      tileColor: isPreselected
          ? colorScheme.primaryContainer.withValues(alpha: 0.4)
          : null,
      leading: isPreselected
          ? Icon(Icons.check_circle, color: colorScheme.primary)
          : Icon(Icons.radio_button_unchecked, color: colorScheme.outline),
      title: Text(
        type.displayLabel,
        style: isPreselected
            ? TextStyle(
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
              )
            : null,
      ),
      onTap: () => Navigator.of(context).pop(type),
    );
  }
}
