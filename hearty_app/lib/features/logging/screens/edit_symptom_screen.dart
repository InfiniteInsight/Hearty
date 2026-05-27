import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/hearty_api_client.dart';
import '../../../core/offline/local_symptom_dao.dart';

class EditSymptomScreen extends ConsumerStatefulWidget {
  final String id;
  final String initialDescription;
  final int? initialSeverity;
  final int? initialOnsetMinutes;

  const EditSymptomScreen({
    super.key,
    required this.id,
    required this.initialDescription,
    this.initialSeverity,
    this.initialOnsetMinutes,
  });

  @override
  ConsumerState<EditSymptomScreen> createState() => _EditSymptomScreenState();
}

class _EditSymptomScreenState extends ConsumerState<EditSymptomScreen> {
  late final TextEditingController _descController;
  late final TextEditingController _onsetController;
  late double _severity;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _descController = TextEditingController(text: widget.initialDescription);
    _severity = (widget.initialSeverity ?? 5).toDouble().clamp(1, 10);
    _onsetController = TextEditingController(
      text: widget.initialOnsetMinutes?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _descController.dispose();
    _onsetController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _descController.text.trim();
    if (text.isEmpty) return;
    setState(() => _saving = true);
    try {
      final onsetText = _onsetController.text.trim();
      final onsetMinutes = onsetText.isEmpty ? null : int.tryParse(onsetText);
      final updated = await ref.read(heartyApiClientProvider).updateSymptom(
            widget.id,
            text,
            severity: _severity.round(),
            onsetMinutes: onsetMinutes,
          );
      await ref.read(localSymptomDaoProvider).upsertFromServer(updated);
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
        title: const Text('Edit Symptom'),
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
            const SizedBox(height: 24),
            Text(
              'Severity: ${_severity.round()} / 10',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Slider(
              value: _severity,
              min: 1,
              max: 10,
              divisions: 9,
              label: _severity.round().toString(),
              onChanged: (v) => setState(() => _severity = v),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _onsetController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Onset after eating (minutes)',
                hintText: 'e.g. 30',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
