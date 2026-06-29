import 'package:flutter/material.dart';

import 'add_item_dialog.dart';
import 'aurora_chip_style.dart';

class DietaryProtocolsSection extends StatelessWidget {
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  /// When true, render with the Aurora glass/emerald chip styling
  /// (Health Profile screen). Defaults to false for the plain light-theme
  /// onboarding flow.
  final bool aurora;

  static const _builtIn = [
    'Gluten-Free', 'Dairy-Free', 'Low-FODMAP', 'Vegetarian',
    'Pescetarian', 'Vegan', 'Keto', 'Paleo',
  ];

  const DietaryProtocolsSection({
    super.key,
    required this.selected,
    required this.onChanged,
    this.aurora = false,
  });

  @override
  Widget build(BuildContext context) {
    final custom = selected.where((p) => !_builtIn.contains(p)).toList();
    final all = [..._builtIn, ...custom];
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        ...all.map((p) {
          final isSelected = selected.contains(p);
          return FilterChip(
            label: Text(p),
            selected: isSelected,
            onSelected: (on) => onChanged(
              on
                  ? [...selected, p]
                  : selected.where((x) => x != p).toList(),
            ),
            backgroundColor: aurora ? auroraChipBg(false) : null,
            selectedColor: aurora ? auroraChipBg(true) : null,
            side: aurora ? auroraChipSide(isSelected) : null,
            labelStyle: aurora ? auroraChipLabel(isSelected) : null,
            showCheckmark: aurora ? false : null,
          );
        }),
        ActionChip(
          avatar: Icon(Icons.add,
              size: 16, color: aurora ? auroraChipAddIcon : null),
          label: const Text('Add'),
          backgroundColor: aurora ? auroraChipBg(false) : null,
          side: aurora ? auroraChipSide(false) : null,
          labelStyle: aurora ? auroraChipLabel(false) : null,
          onPressed: () async {
            final text =
                await showAddItemDialog(context, 'Add Dietary Protocol');
            if (text != null && !selected.contains(text)) {
              onChanged([...selected, text]);
            }
          },
        ),
      ],
    );
  }
}
