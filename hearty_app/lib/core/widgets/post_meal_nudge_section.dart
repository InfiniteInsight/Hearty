import 'package:flutter/material.dart';

/// Post-meal nudge toggle + delay slider, shared between onboarding and settings.
///
/// [compact] = true  → onboarding layout (no subtitle, zero switch padding, inline delay label)
/// [compact] = false → settings layout (subtitle, default padding, Row label/value)
class PostMealNudgeSection extends StatelessWidget {
  final bool enabled;
  final int delayMinutes;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onDelayChanged;
  final bool compact;

  static const int _minDelay = 5;
  static const int _maxDelay = 90;
  static const int _step = 5;

  const PostMealNudgeSection({
    super.key,
    required this.enabled,
    required this.delayMinutes,
    required this.onToggle,
    required this.onDelayChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: const Text('Post-meal nudge'),
          subtitle: compact
              ? null
              : const Text('Follow-up check-in after logging a meal'),
          value: enabled,
          onChanged: onToggle,
          contentPadding: compact ? EdgeInsets.zero : null,
        ),
        if (enabled) _buildSlider(context),
      ],
    );
  }

  Widget _buildSlider(BuildContext context) {
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text('Delay: $delayMinutes min',
              style: Theme.of(context).textTheme.bodyMedium),
          _slider(),
        ],
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Delay'),
              Text('$delayMinutes min',
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        _slider(),
      ],
    );
  }

  Widget _slider() {
    return Slider(
      value: delayMinutes.toDouble(),
      min: _minDelay.toDouble(),
      max: _maxDelay.toDouble(),
      divisions: (_maxDelay - _minDelay) ~/ _step,
      label: '$delayMinutes min',
      onChanged: (v) => onDelayChanged((v / _step).round() * _step),
    );
  }
}
