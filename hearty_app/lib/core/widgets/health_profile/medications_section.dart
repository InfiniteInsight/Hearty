import 'package:flutter/material.dart';

import '../../../app/theme/aurora_colors.dart';
import 'aurora_chip_style.dart';

class MedicationsSection extends StatefulWidget {
  final List<String> medications;
  final ValueChanged<List<String>> onChanged;

  /// When true, render with the Aurora glass field + emerald chip styling
  /// (Health Profile screen). Defaults to false for the plain light-theme
  /// onboarding flow.
  final bool aurora;

  const MedicationsSection({
    super.key,
    required this.medications,
    required this.onChanged,
    this.aurora = false,
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
    final aurora = widget.aurora;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          style: aurora ? const TextStyle(color: Aurora.textPrimary) : null,
          decoration: InputDecoration(
            hintText: 'Add medication or supplement',
            hintStyle:
                aurora ? const TextStyle(color: Aurora.textMuted) : null,
            filled: aurora ? true : null,
            fillColor: aurora ? Aurora.glassFill : null,
            enabledBorder: aurora
                ? OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Aurora.glassBorder),
                  )
                : null,
            focusedBorder: aurora
                ? OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Aurora.accentGreen),
                  )
                : null,
            suffixIcon: IconButton(
              icon: Icon(Icons.add,
                  color: aurora ? Aurora.textSecondary : null),
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
                      backgroundColor: aurora ? auroraChipBg(true) : null,
                      side: aurora ? auroraChipSide(true) : null,
                      labelStyle: aurora ? auroraChipLabel(true) : null,
                      deleteIconColor:
                          aurora ? auroraChipDeleteIcon : null,
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
