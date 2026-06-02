import 'package:flutter/material.dart';

import 'add_item_dialog.dart';

class AllergensSection extends StatelessWidget {
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  static const _builtIn = [
    'Gluten', 'Dairy', 'Eggs', 'Tree Nuts', 'Peanuts',
    'Soy', 'Shellfish', 'Fish', 'Sesame',
  ];

  const AllergensSection({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final custom = selected.where((a) => !_builtIn.contains(a)).toList();
    final all = [..._builtIn, ...custom];
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        ...all.map((a) => FilterChip(
              label: Text(a),
              selected: selected.contains(a),
              onSelected: (on) => onChanged(
                on
                    ? [...selected, a]
                    : selected.where((x) => x != a).toList(),
              ),
            )),
        ActionChip(
          avatar: const Icon(Icons.add, size: 16),
          label: const Text('Add'),
          onPressed: () async {
            final text = await showAddItemDialog(context, 'Add Allergen');
            if (text != null && !selected.contains(text)) {
              onChanged([...selected, text]);
            }
          },
        ),
      ],
    );
  }
}
