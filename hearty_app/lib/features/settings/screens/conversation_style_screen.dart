import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers/preferences_provider.dart';

class ConversationStyleScreen extends ConsumerStatefulWidget {
  const ConversationStyleScreen({super.key});

  @override
  ConsumerState<ConversationStyleScreen> createState() =>
      _ConversationStyleScreenState();
}

class _ConversationStyleScreenState
    extends ConsumerState<ConversationStyleScreen> {
  late String _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = ref.read(preferencesProvider).valueOrNull?.conversationStyle ?? 'warm';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final existing = ref.read(preferencesProvider).valueOrNull;
    if (existing == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Still loading — please try again')),
        );
      }
      setState(() => _saving = false);
      return;
    }
    await ref.read(preferencesProvider.notifier).save(
          existing.copyWith(conversationStyle: _selected),
        );
    if (!mounted) return;
    final result = ref.read(preferencesProvider);
    if (result.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save — please try again')),
      );
    }
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conversation Style')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Choose how Hearty talks to you during logging and check-ins.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          _StyleCard(
            value: 'warm',
            selected: _selected,
            icon: '❤️',
            title: 'Warm & Empathetic',
            subtitle: 'Hearty adds warmth and context to responses. Great if you want to feel supported.',
            exampleExchanges: const [
              ('Had a big bowl of pasta for dinner',
               'Comfort food evening! 🍝 I\'ve noted that. Since pasta can vary quite a bit — was it homemade or from a restaurant?'),
              ('Feeling really tired and bloated',
               'I\'m sorry you\'re not feeling your best 💙 I\'ve logged that for you.'),
            ],
            onTap: () => setState(() => _selected = 'warm'),
          ),
          const SizedBox(height: 12),
          _StyleCard(
            value: 'concise',
            selected: _selected,
            icon: '⚡',
            title: 'Concise & Quick',
            subtitle: 'Just the facts. Hearty logs and confirms without commentary or added warmth.',
            exampleExchanges: const [
              ('Had a big bowl of pasta for dinner', 'Logged. Homemade or restaurant?'),
              ('Feeling really tired and bloated', 'Logged.'),
            ],
            onTap: () => setState(() => _selected = 'concise'),
          ),
          const SizedBox(height: 24),
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

class _StyleCard extends StatelessWidget {
  final String value;
  final String selected;
  final String icon;
  final String title;
  final String subtitle;
  final List<(String user, String hearty)> exampleExchanges;
  final VoidCallback onTap;

  const _StyleCard({
    required this.value,
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.exampleExchanges,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == selected;
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
            width: 2,
          ),
          color: isSelected
              ? colorScheme.primary.withValues(alpha: 0.05)
              : colorScheme.surface,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$icon $title',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                Icon(
                  isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: isSelected ? colorScheme.primary : colorScheme.outline,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: isSelected
                    ? colorScheme.primaryContainer.withValues(alpha: 0.4)
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'EXAMPLE',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          letterSpacing: 0.5,
                        ),
                  ),
                  const SizedBox(height: 8),
                  for (final (userMsg, heartyMsg) in exampleExchanges) ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6, left: 32),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(12),
                            topRight: Radius.circular(12),
                            bottomLeft: Radius.circular(12),
                          ),
                        ),
                        child: Text(
                          userMsg,
                          style: TextStyle(
                              color: colorScheme.onPrimary, fontSize: 12),
                        ),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.only(bottom: 8, right: 32),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        border: Border.all(color: colorScheme.outlineVariant),
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(12),
                          bottomLeft: Radius.circular(12),
                          bottomRight: Radius.circular(12),
                        ),
                      ),
                      child: Text(
                        heartyMsg,
                        style: TextStyle(
                            color: colorScheme.onSurface, fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
