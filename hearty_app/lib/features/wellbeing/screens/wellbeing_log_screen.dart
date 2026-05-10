import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/hearty_api_client.dart';
import '../../../core/api/providers/wellbeing_provider.dart';

class WellbeingLogScreen extends ConsumerStatefulWidget {
  const WellbeingLogScreen({super.key});

  @override
  ConsumerState<WellbeingLogScreen> createState() => _WellbeingLogScreenState();
}

class _WellbeingLogScreenState extends ConsumerState<WellbeingLogScreen> {
  int _energy = 3;
  int _mood = 3;
  final _notesController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(heartyApiClientProvider).logWellbeing(
            energy: _energy,
            mood: _mood,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );
      ref.invalidate(wellbeingProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Morning Wellbeing')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _ScaleRow(
            label: 'Energy',
            icon: Icons.bolt,
            value: _energy,
            onChanged: (v) => setState(() => _energy = v),
          ),
          const SizedBox(height: 24),
          _ScaleRow(
            label: 'Mood',
            icon: Icons.sentiment_satisfied,
            value: _mood,
            onChanged: (v) => setState(() => _mood = v),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _ScaleRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final int value;
  final ValueChanged<int> onChanged;

  const _ScaleRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(label,
                style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            Text('$value / 5',
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(5, (i) {
            final v = i + 1;
            return GestureDetector(
              onTap: () => onChanged(v),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value == v
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$v',
                  style: TextStyle(
                    color: value == v
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}
