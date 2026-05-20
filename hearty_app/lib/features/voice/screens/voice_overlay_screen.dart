import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/voice_state.dart';
import '../providers/voice_provider.dart';
import '../widgets/waveform_animation.dart';
import '../widgets/thinking_animation.dart';

class VoiceOverlayScreen extends ConsumerStatefulWidget {
  const VoiceOverlayScreen({super.key});

  @override
  ConsumerState<VoiceOverlayScreen> createState() => _VoiceOverlayScreenState();
}

class _VoiceOverlayScreenState extends ConsumerState<VoiceOverlayScreen> {
  final _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final voiceState = ref.watch(voiceProvider);

    // Auto-dismiss when idle
    ref.listen(voiceProvider, (_, next) {
      if (next.status == VoiceStatus.idle && mounted) {
        Navigator.of(context).pop();
      }
    });

    // Send to chat API on initial log; route follow-up to symptom logging.
    ref.listen(voiceProvider.select((s) => s.status), (previous, status) {
      if (status == VoiceStatus.thinking) {
        if (previous == VoiceStatus.awaitingFollowUp) {
          ref.read(voiceProvider.notifier).sendFollowUpToApi();
        } else {
          ref.read(voiceProvider.notifier).sendToChat();
        }
      }
    });

    return GestureDetector(
      onTap: () {
        if (ref.read(voiceProvider).status == VoiceStatus.responding) {
          ref.read(voiceProvider.notifier).stopSpeaking();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black.withValues(alpha: 0.85),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => ref.read(voiceProvider.notifier).dismiss(),
                  ),
                ),
                const Spacer(),
                Center(child: _buildAnimation(voiceState.status)),
                const SizedBox(height: 32),
                _buildTextDisplay(voiceState),
                const Spacer(),
                _buildTextInput(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimation(VoiceStatus status) {
    switch (status) {
      case VoiceStatus.listening:
      case VoiceStatus.awaitingFollowUp:
        return const WaveformAnimation();
      case VoiceStatus.thinking:
        return const ThinkingAnimation();
      case VoiceStatus.responding:
        return const Icon(Icons.volume_up, color: Colors.white, size: 48);
      case VoiceStatus.idle:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTextDisplay(VoiceState state) {
    final text =
        (state.status == VoiceStatus.responding || state.status == VoiceStatus.awaitingFollowUp)
            ? state.response
            : state.transcript;
    if (text.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.5),
          textAlign: TextAlign.center,
        ),
        if (state.status == VoiceStatus.listening && text.isNotEmpty)
          TextButton.icon(
            onPressed: () => ref.read(voiceProvider.notifier).startListening(),
            icon: const Icon(Icons.refresh, color: Colors.white70),
            label: const Text('Retry', style: TextStyle(color: Colors.white70)),
          ),
      ],
    );
  }

  Widget _buildTextInput() {
    return TextField(
      controller: _textController,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Or type here...',
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        suffixIcon: IconButton(
          icon: const Icon(Icons.send, color: Colors.white),
          onPressed: _submitText,
        ),
      ),
      onSubmitted: (_) => _submitText(),
    );
  }

  void _submitText() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    ref.read(voiceProvider.notifier).setTranscript(text);
    ref.read(voiceProvider.notifier).setThinking();
  }
}
