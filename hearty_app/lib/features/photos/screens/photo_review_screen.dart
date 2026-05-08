import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/providers/meals_provider.dart';
import '../models/photo_status_response.dart';
import '../models/photo_type.dart';

/// Results review screen shown after photo processing completes.
///
/// Displays allergen warnings, detected foods, an editable description field,
/// and actions to save the meal log or retake the photo.
class PhotoReviewScreen extends ConsumerStatefulWidget {
  const PhotoReviewScreen({
    super.key,
    required this.statusResponse,
    required this.photoType,
  });

  final PhotoStatusResponse statusResponse;
  final PhotoType photoType;

  @override
  ConsumerState<PhotoReviewScreen> createState() => _PhotoReviewScreenState();
}

class _PhotoReviewScreenState extends ConsumerState<PhotoReviewScreen> {
  late final TextEditingController _descController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final foods = widget.statusResponse.foods;
    final initialDescription = foods.isNotEmpty
        ? foods
            .map((f) => f['name'] as String? ?? '')
            .where((n) => n.isNotEmpty)
            .join(', ')
        : 'Photo result';
    _descController = TextEditingController(text: initialDescription);
  }

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(mealsProvider.notifier).logMeal(
            _descController.text.trim(),
          );
      if (mounted) context.go('/home');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save — please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusResponse = widget.statusResponse;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final allergenWarnings = statusResponse.allergenWarnings;
    final foods = statusResponse.foods;

    return Scaffold(
      appBar: AppBar(title: const Text('Review Photo Results')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Allergen warning banner ────────────────────────────────────
            if (allergenWarnings.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade400),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.amber.shade800,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Allergen Warnings',
                          style: textTheme.titleSmall?.copyWith(
                            color: Colors.amber.shade900,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...allergenWarnings.map(
                      (warning) => Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '⚠ $warning',
                          style: TextStyle(color: Colors.amber.shade900),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Detected items section ─────────────────────────────────────
            if (foods.isNotEmpty) ...[
              Text(
                widget.photoType == PhotoType.nutritionLabel
                    ? 'Nutritional Information'
                    : 'Detected Foods',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ...foods.map((food) {
                final name = food['name'] as String? ?? '';
                final quantity = food['quantity'] as String?;
                final calories = food['estimated_calories'];

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (quantity != null && quantity.isNotEmpty)
                          Text(quantity),
                        if (calories != null)
                          Text('~$calories cal'),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
            ],

            // ── Editable description field ─────────────────────────────────
            TextField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
              maxLines: null,
            ),

            const SizedBox(height: 24),

            // ── Save button ────────────────────────────────────────────────
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Looks good — Save'),
            ),

            const SizedBox(height: 8),

            // ── Retake button ──────────────────────────────────────────────
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Retake photo'),
            ),
          ],
        ),
      ),
    );
  }
}
