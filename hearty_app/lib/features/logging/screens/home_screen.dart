import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../voice/providers/voice_provider.dart';
import '../../voice/screens/voice_overlay_screen.dart';
import '../../wake_word/providers/wake_word_provider.dart';
import '../../wake_word/wake_word_channel.dart';
import '../../../core/audio/chime_player.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Wake word → chime → voice overlay
    ref.listen(wakeWordDetectedProvider, (_, detected) async {
      if (!detected) return;
      await ChimePlayer.instance.play();
      if (!context.mounted) return;
      ref.read(voiceProvider.notifier).startListening();
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const VoiceOverlayScreen(),
      );
      ref.read(wakeWordDetectedProvider.notifier).setDetected(false);
      await WakeWordChannel.startListening();
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Hearty')),
      body: const Center(child: Text("Today's timeline coming in Phase 5")),
      floatingActionButton: _QuickLogFab(
        onVoiceTap: () => _openVoiceOverlay(context, ref),
        onTextTap: () => context.push('/log'),
        onCameraTap: () => context.push('/log'),
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

class _QuickLogFab extends StatefulWidget {
  final VoidCallback onVoiceTap;
  final VoidCallback onTextTap;
  final VoidCallback onCameraTap;

  const _QuickLogFab({
    required this.onVoiceTap,
    required this.onTextTap,
    required this.onCameraTap,
  });

  @override
  State<_QuickLogFab> createState() => _QuickLogFabState();
}

class _QuickLogFabState extends State<_QuickLogFab> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_expanded) ...[
          _SubFab(icon: Icons.mic, label: 'Voice', onTap: () {
            setState(() => _expanded = false);
            widget.onVoiceTap();
          }),
          const SizedBox(height: 8),
          _SubFab(icon: Icons.edit, label: 'Text', onTap: () {
            setState(() => _expanded = false);
            widget.onTextTap();
          }),
          const SizedBox(height: 8),
          _SubFab(icon: Icons.camera_alt, label: 'Camera', onTap: () {
            setState(() => _expanded = false);
            widget.onCameraTap();
          }),
          const SizedBox(height: 12),
        ],
        FloatingActionButton(
          onPressed: () => setState(() => _expanded = !_expanded),
          child: Icon(_expanded ? Icons.close : Icons.add),
        ),
      ],
    );
  }
}

class _SubFab extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SubFab({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xDD000000),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
        const SizedBox(width: 8),
        FloatingActionButton.small(
          heroTag: label,
          onPressed: onTap,
          child: Icon(icon),
        ),
      ],
    );
  }
}
