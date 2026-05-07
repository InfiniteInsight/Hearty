import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../voice/providers/voice_provider.dart';
import '../../voice/screens/voice_overlay_screen.dart';

class LogEntryScreen extends ConsumerWidget {
  const LogEntryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Log Entry')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Center(
              child: GestureDetector(
                onTap: () => _openVoiceOverlay(context, ref),
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  child: const Icon(Icons.mic, color: Colors.white, size: 56),
                ),
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              decoration: InputDecoration(
                hintText: 'Or type what you ate...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: const Icon(Icons.send),
              ),
              onSubmitted: (text) {
                // Phase 5 will wire this to the API
              },
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: ['Coffee', 'Oatmeal', 'Water']
                  .map((label) => ActionChip(
                        label: Text(label),
                        onPressed: () {},
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openVoiceOverlay(BuildContext context, WidgetRef ref) async {
    ref.read(voiceProvider.notifier).startListening();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const VoiceOverlayScreen(),
    );
  }
}
