import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../app/theme/aurora_colors.dart';
import '../../../core/api/hearty_api_client.dart';
import '../../../core/offline/local_meal_dao.dart';
import '../widgets/editable_food_list.dart';

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
  final GlobalKey<EditableFoodListState> _foodsKey =
      GlobalKey<EditableFoodListState>();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _descController = TextEditingController(text: widget.initialDescription);
  }

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  /// Current non-empty food names, in order.
  List<String> _currentFoods() =>
      _foodsKey.currentState?.currentFoods() ?? const [];

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
    return Theme(
      data: AppTheme.aurora,
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: Aurora.background),
        child: Scaffold(
          backgroundColor: Colors.transparent,
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: TextButton(
                    onPressed: _save,
                    style: TextButton.styleFrom(
                      foregroundColor: Aurora.accentGreen,
                    ),
                    child: const Text('Save'),
                  ),
                ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Aurora.glassFill,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Aurora.glassBorder),
                  ),
                  child: TextField(
                    controller: _descController,
                    autofocus: true,
                    minLines: 3,
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(color: Aurora.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Description',
                      labelStyle: const TextStyle(color: Aurora.textMuted),
                      filled: true,
                      fillColor: Aurora.glassFill,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Aurora.glassBorder),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Aurora.glassBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Aurora.accentGreen),
                      ),
                    ),
                  ),
                ),
                if (widget.initialFoods.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Foods identified',
                    style: TextStyle(
                      color: Aurora.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  EditableFoodList(
                    key: _foodsKey,
                    initialFoods: widget.initialFoods,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
