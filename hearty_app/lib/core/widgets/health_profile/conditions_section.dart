import 'package:flutter/material.dart';

import 'add_item_dialog.dart';

class ConditionsSection extends StatelessWidget {
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  static const _common = [
    'IBS', 'Celiac Disease', "Crohn's Disease", 'Ulcerative Colitis',
    'GERD', 'SIBO', 'Diverticulitis', 'Lactose Intolerance',
  ];

  const ConditionsSection({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final custom = selected.where((c) => !_common.contains(c)).toList();
    final all = [..._common, ...custom];
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        ...all.map((c) => FilterChip(
              label: Text(c),
              selected: selected.contains(c),
              onSelected: (on) => onChanged(
                on
                    ? [...selected, c]
                    : selected.where((x) => x != c).toList(),
              ),
            )),
        ActionChip(
          avatar: const Icon(Icons.add, size: 16),
          label: const Text('Add'),
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
