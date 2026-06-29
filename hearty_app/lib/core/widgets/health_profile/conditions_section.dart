import 'package:flutter/material.dart';

import 'add_item_dialog.dart';
import 'aurora_chip_style.dart';

class ConditionsSection extends StatelessWidget {
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  /// When true, render with the Aurora glass/emerald chip styling
  /// (Health Profile screen). Defaults to false for the plain light-theme
  /// onboarding flow.
  final bool aurora;

  static const _common = [
    'IBS', 'Celiac Disease', "Crohn's Disease", 'Ulcerative Colitis',
    'GERD', 'SIBO', 'Diverticulitis', 'Lactose Intolerance',
  ];

  const ConditionsSection({
    super.key,
    required this.selected,
    required this.onChanged,
    this.aurora = false,
  });

  @override
  Widget build(BuildContext context) {
    final custom = selected.where((c) => !_common.contains(c)).toList();
    final all = [..._common, ...custom];
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        ...all.map((c) {
          final isSelected = selected.contains(c);
          return FilterChip(
            label: Text(c),
            selected: isSelected,
            onSelected: (on) => onChanged(
              on
                  ? [...selected, c]
                  : selected.where((x) => x != c).toList(),
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
            final text = await showAddItemDialog(context, 'Add Condition');
            if (text != null && !selected.contains(text)) {
              onChanged([...selected, text]);
            }
          },
        ),
      ],
    );
  }
}
