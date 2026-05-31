import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/hearty_api_client.dart';
import '../../../core/offline/local_meal_dao.dart';

class EditMealScreen extends ConsumerStatefulWidget {
  final String id;
  final String initialDescription;
  final List<String> initialFoods;

  const EditMealScreen({
    super.key,
    required this.id,
    required this.initialDescription,
    this.initialFoods = const [],
  });

  @override
  ConsumerState<EditMealScreen> createState() => _EditMealScreenState();
}

class _EditMealScreenState extends ConsumerState<EditMealScreen> {
  late final TextEditingController _descController;
  late final List<TextEditingController> _foodControllers;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _descController = TextEditingController(text: widget.initialDescription);
    _foodControllers = widget.initialFoods
        .map((f) => TextEditingController(text: f))
        .toList();
  }

  @override
  void dispose() {
    _descController.dispose();
    for (final c in _foodControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _removeFood(int index) {
    setState(() {
      final removed = _foodControllers.removeAt(index);
      removed.dispose();
    });
  }

  /// Current non-empty food names, in order.
  List<String> _currentFoods() => _foodControllers
      .map((c) => c.text.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  Future<void> _save() async {
    final text = _descController.text.trim();
    if (text.isEmpty) return;
    setState(() => _saving = true);
    try {
      final currentFoods = _currentFoods();
      final initialFiltered = widget.initialFoods
          .map((f) => f.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      // "Touched" = the current food values differ from what was loaded
      // (order-sensitive value comparison, not focus). Untouched -> send
      // description only so the backend re-extracts; touched -> send verbatim.
      final foodsTouched = !listEquals(currentFoods, initialFiltered);

      final updated = await ref.read(heartyApiClientProvider).updateMeal(
            widget.id,
            text,
            foods: foodsTouched ? currentFoods : null,
          );
      await ref.read(localMealDaoProvider).upsertFromServer(updated);
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save — try again')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Meal'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _descController,
              autofocus: true,
              minLines: 3,
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
            if (_foodControllers.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'Foods identified',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _foodControllers.length; i++)
                Padding(
                  key: ValueKey(_foodControllers[i]),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _foodControllers[i],
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
            ],
          ],
        ),
      ),
    );
  }
}
