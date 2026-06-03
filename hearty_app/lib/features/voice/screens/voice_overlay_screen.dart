import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/voice_state.dart';
import '../providers/voice_provider.dart';
import '../widgets/prism_waveform.dart';
import '../widgets/thinking_animation.dart';

class VoiceOverlayScreen extends ConsumerStatefulWidget {
  const VoiceOverlayScreen({super.key});

  @override
  ConsumerState<VoiceOverlayScreen> createState() => _VoiceOverlayScreenState();
}

class _VoiceOverlayScreenState extends ConsumerState<VoiceOverlayScreen> {
  final _textController = TextEditingController();
  // Live mic amplitude feeding the prism visualiser. TODO(amplitude-source):
  // currently a constant 0 (calm idle beam) — wire to the real STT sound-level
  // once the dictation amplitude source is resolved (see project memory).
  final ValueNotifier<double> _micLevel = ValueNotifier<double>(0.0);

  @override
  void dispose() {
    _textController.dispose();
    _micLevel.dispose();
    super.dispose();
  }

  /// The luminous prism waveform band shown while the mic is live.
  Widget _voiceVisualizer() => SizedBox(
        width: double.infinity,
        height: 140,
        child: PrismWaveform(level: _micLevel),
      );

  @override
  Widget build(BuildContext context) {
    final voiceState = ref.watch(voiceProvider);

    // Auto-dismiss when idle
    ref.listen(voiceProvider, (_, next) {
      if (next.status == VoiceStatus.idle && mounted) {
        Navigator.of(context).pop();
      }
    });

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
                Center(child: _buildAnimation(voiceState)),
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

  Widget _buildAnimation(VoiceState state) {
    switch (state.status) {
      case VoiceStatus.listening:
        return _voiceVisualizer();
      case VoiceStatus.awaitingFollowUp:
        switch (state.micPhase) {
          case MicPhase.listening:
            return _voiceVisualizer();
          case MicPhase.paused:
            return IconButton(
              key: const Key('tap_to_talk_button'),
              iconSize: 56,
              icon: const Icon(Icons.mic_none, color: Colors.white),
              tooltip: 'Tap to talk',
              onPressed: () =>
                  ref.read(voiceProvider.notifier).resumeFollowUpListening(),
            );
          case MicPhase.preparing:
          case MicPhase.none:
            return SizedBox(
              key: const Key('getting_ready_hint'),
              height: 56,
              width: 56,
              child: Semantics(
                label: 'Getting ready',
                child: const CircularProgressIndicator(color: Colors.white70),
              ),
            );
        }
      case VoiceStatus.thinking:
        return const ThinkingAnimation();
      case VoiceStatus.responding:
        return const Icon(Icons.volume_up, color: Colors.white, size: 48);
      case VoiceStatus.idle:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTextDisplay(VoiceState state) {
    if (state.status == VoiceStatus.awaitingFollowUp) {
      return _buildFollowUpDisplay(state);
    }

    final text = state.status == VoiceStatus.responding ? state.response : state.transcript;
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
          _buildSubmitRow(canRetry: true),
      ],
    );
  }

  // During the follow-up turn: show the AI's question dimmed above, and the
  // user's in-progress answer below so they can see what's being captured.
  Widget _buildFollowUpDisplay(VoiceState state) {
    final hasTranscript = state.transcript.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.response.isNotEmpty)
          Text(
            state.response,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 16,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        if (state.micPhase == MicPhase.preparing) ...[
          const SizedBox(height: 12),
          Text(
            'Getting ready…',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
          ),
        ],
        if (state.micPhase == MicPhase.paused) ...[
          const SizedBox(height: 12),
          Text(
            'Tap the mic when you’re ready',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
          ),
        ],
        if (hasTranscript) ...[
          const SizedBox(height: 12),
          Text(
            state.transcript,
            style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.5),
            textAlign: TextAlign.center,
          ),
          _buildSubmitRow(canRetry: false),
        ],
      ],
    );
  }

  Widget _buildSubmitRow({required bool canRetry}) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: () => ref.read(voiceProvider.notifier).setThinking(),
            icon: const Icon(Icons.send),
            label: const Text('Submit'),
          ),
          if (canRetry) ...[
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: () => ref.read(voiceProvider.notifier).startListening(),
              icon: const Icon(Icons.refresh, color: Colors.white70),
              label: const Text('Re-record', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ],
      ),
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
