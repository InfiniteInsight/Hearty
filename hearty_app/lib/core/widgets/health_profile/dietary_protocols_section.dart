import 'package:flutter/material.dart';

import 'add_item_dialog.dart';

class DietaryProtocolsSection extends StatelessWidget {
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  static const _builtIn = [
    'Gluten-Free', 'Dairy-Free', 'Low-FODMAP', 'Vegetarian',
    'Pescetarian', 'Vegan', 'Keto', 'Paleo',
  ];

  const DietaryProtocolsSection({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final custom = selected.where((p) => !_builtIn.contains(p)).toList();
    final all = [..._builtIn, ...custom];
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        ...all.map((p) => FilterChip(
              label: Text(p),
              selected: selected.contains(p),
              onSelected: (on) => onChanged(
                on
                    ? [...selected, p]
                    : selected.where((x) => x != p).toList(),
              ),
            )),
        ActionChip(
          avatar: const Icon(Icons.add, size: 16),
          label: const Text('Add'),
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
