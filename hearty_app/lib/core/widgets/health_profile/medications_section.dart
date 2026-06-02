import 'package:flutter/material.dart';

class MedicationsSection extends StatefulWidget {
  final List<String> medications;
  final ValueChanged<List<String>> onChanged;

  const MedicationsSection({
    super.key,
    required this.medications,
    required this.onChanged,
  });

  @override
  State<MedicationsSection> createState() => _MedicationsSectionState();
}

class _MedicationsSectionState extends State<MedicationsSection> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      widget.onChanged([...widget.medications, text]);
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            hintText: 'Add medication or supplement',
            suffixIcon: IconButton(
              icon: const Icon(Icons.add),
              onPressed: _submit,
            ),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
        if (widget.medications.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: widget.medications
                .map((m) => InputChip(
                      label: Text(m),
                      onDeleted: () => widget.onChanged(
                        widget.medications.where((x) => x != m).toList(),
                      ),
                    ))
                .toList(),
          ),
        ],
      ],
    );
  }
}
