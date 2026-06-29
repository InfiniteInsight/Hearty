import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/theme.dart';
import '../../../app/theme/aurora_colors.dart';

class ConversationStyleSetupScreen extends StatefulWidget {
  const ConversationStyleSetupScreen({super.key});

  @override
  State<ConversationStyleSetupScreen> createState() =>
      _ConversationStyleSetupScreenState();
}

class _ConversationStyleSetupScreenState
    extends State<ConversationStyleSetupScreen> {
  String _selected = 'warm';
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('conversation_style', _selected);
    await prefs.setBool('conversation_style_configured', true);
    if (mounted) context.pop();
  }

  Future<void> _skip() async {
    if (_saving) return;
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('conversation_style', 'warm');
    await prefs.setBool('conversation_style_configured', true);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.aurora,
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: Aurora.background),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('💬', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 16),
                  Text(
                    'How should Hearty talk to you?',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Aurora.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'You can change this anytime in Settings.',
                    style: TextStyle(
                        color: Aurora.textSecondary, fontSize: 14, height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  _StyleCard(
                    value: 'warm',
                    selected: _selected,
                    icon: '❤️',
                    title: 'Warm & Empathetic',
                    subtitle: 'Supportive responses with context and warmth.',
                    exampleReply:
                        'Comfort food evening! 🍝 Was that homemade or from a restaurant?',
                    onTap: () => setState(() => _selected = 'warm'),
                  ),
                  const SizedBox(height: 12),
                  _StyleCard(
                    value: 'concise',
                    selected: _selected,
                    icon: '⚡',
                    title: 'Concise & Quick',
                    subtitle: 'Just the essentials — log it and move on.',
                    exampleReply: 'Logged. Homemade or restaurant?',
                    onTap: () => setState(() => _selected = 'concise'),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: Aurora.accentGreen,
                        foregroundColor: const Color(0xFF052E20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFF052E20)),
                            )
                          : const Text('Looks good →'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _saving ? null : _skip,
                    child: const Text(
                      'Skip for now',
                      style:
                          TextStyle(color: Aurora.textSecondary, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StyleCard extends StatelessWidget {
  final String value;
  final String selected;
  final String icon;
  final String title;
  final String subtitle;
  final String exampleReply;
  final VoidCallback onTap;

  const _StyleCard({
    required this.value,
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.exampleReply,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == selected;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Aurora.accentGreen : Aurora.glassBorder,
            width: 2,
          ),
          color: isSelected
              ? Aurora.accentGreen.withValues(alpha: 0.18)
              : Aurora.glassFill,
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$icon $title',
                    style: const TextStyle(
                      color: Aurora.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style:
                        const TextStyle(color: Aurora.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  // Example: user bubble
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Aurora.accentGreen,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(12),
                          bottomLeft: Radius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Had pasta for dinner',
                        style: TextStyle(color: Color(0xFF052E20), fontSize: 11),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Example: Hearty reply bubble
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Aurora.glassFill,
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(12),
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                    ),
                    child: Text(
                      exampleReply,
                      style: const TextStyle(
                          color: Aurora.textSecondary, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isSelected ? Aurora.accentGreen : Aurora.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
