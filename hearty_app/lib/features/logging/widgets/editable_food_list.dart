import 'package:flutter/material.dart';

/// A reusable, self-contained editable list of food names.
///
/// Owns a [TextEditingController] per row, renders each as a [TextField] with a
/// remove (✕) button, plus an "Add food" button that appends an empty row. It
/// performs no persistence/API work — it only edits a list of names. A parent
/// reads the current names via a [GlobalKey] and [currentFoods], mirroring how
/// `EditMealScreen` pulled its food values on save.
class EditableFoodList extends StatefulWidget {
  final List<String> initialFoods;

  /// Optional: emits the current trimmed, non-empty foods whenever they change
  /// (edit / remove / add). A parent that prefers a push model can use this
  /// instead of a [GlobalKey] + [currentFoods].
  final ValueChanged<List<String>>? onChanged;

  const EditableFoodList({
    super.key,
    this.initialFoods = const [],
    this.onChanged,
  });

  @override
  State<EditableFoodList> createState() => EditableFoodListState();
}

class EditableFoodListState extends State<EditableFoodList> {
  late final List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = widget.initialFoods
        .map((f) => TextEditingController(text: f))
        .toList();
    for (final c in _controllers) {
      c.addListener(_notify);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  /// Current non-empty food names, trimmed, in order.
  List<String> currentFoods() => _controllers
      .map((c) => c.text.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  void _notify() => widget.onChanged?.call(currentFoods());

  void _removeFood(int index) {
    setState(() {
      final removed = _controllers.removeAt(index);
      removed.dispose();
    });
    _notify();
  }

  void _addFood() {
    setState(() {
      final c = TextEditingController();
      c.addListener(_notify);
      _controllers.add(c);
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _controllers.length; i++)
          Padding(
            key: ValueKey(_controllers[i]),
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controllers[i],
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Remove food',
                  onPressed: () => _removeFood(i),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addFood,
            icon: const Icon(Icons.add),
            label: const Text('Add food'),
          ),
        ),
      ],
    );
  }
}
