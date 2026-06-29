import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../app/theme.dart';
import '../../../app/theme/aurora_colors.dart';
import '../models/voice_state.dart';
import '../providers/voice_provider.dart';
import '../widgets/prism_waveform.dart';
import '../widgets/thinking_animation.dart';
import '../../wake_word/wake_word_channel.dart';

class VoiceOverlayScreen extends ConsumerStatefulWidget {
  const VoiceOverlayScreen({super.key});

  @override
  ConsumerState<VoiceOverlayScreen> createState() => _VoiceOverlayScreenState();
}

class _VoiceOverlayScreenState extends ConsumerState<VoiceOverlayScreen> {
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Keep the screen awake for the whole voice session so it doesn't sleep
    // mid-dictation. Released in dispose().
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _textController.dispose();
    // The voice session is over — re-arm the wake-word service mic that
    // _beginStt handed off. This is the single session-end chokepoint covering
    // every entry path (wake word, follow-up notification, tap-to-talk).
    // No-ops if wake word is disabled (service not running -> channel throws).
    WakeWordChannel.startListening().catchError((_) {});
    super.dispose();
  }

  /// The luminous prism waveform band shown while the mic is live, driven by
  /// the provider's live mic sound level (from the STT recognizer).
  Widget _voiceVisualizer() => SizedBox(
        width: double.infinity,
        height: 140,
        child: PrismWaveform(level: ref.read(voiceProvider.notifier).soundLevel),
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
      child: Theme(
        data: AppTheme.aurora,
        child: Scaffold(
          backgroundColor: Aurora.bgBottom.withValues(alpha: 0.92),
          body: SafeArea(
            // Vertical padding only — horizontal padding is applied per-child so
            // the prism visualiser row can span the full screen width (edge to
            // edge) while the other content stays inset by 24.
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Aurora.textSecondary),
                      onPressed: () => ref.read(voiceProvider.notifier).dismiss(),
                    ),
                  ),
                ),
                const Spacer(),
                // Full-bleed: no horizontal padding so the wave touches the edges.
                Center(child: _buildAnimation(voiceState)),
                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _buildTextDisplay(voiceState),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _buildTextInput(),
                ),
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimation(VoiceState state) {
    switch (state.status) {
      case VoiceStatus.listening:
        // Mirror the awaitingFollowUp handling: the mic isn't always live the
        // instant the overlay opens. A cold on-device model warms for a few
        // seconds first (preparing → spinner); if it can't, we drop to manual
        // (paused → tap-to-talk) instead of showing a dead flat prism.
        switch (state.micPhase) {
          case MicPhase.listening:
            return _voiceVisualizer();
          case MicPhase.paused:
            return _tapToTalkButton(
                () => ref.read(voiceProvider.notifier).startListening());
          case MicPhase.preparing:
          case MicPhase.none:
            return _gettingReadyIndicator();
        }
      case VoiceStatus.awaitingFollowUp:
        switch (state.micPhase) {
          case MicPhase.listening:
            return _voiceVisualizer();
          case MicPhase.paused:
            return _tapToTalkButton(
                () => ref.read(voiceProvider.notifier).resumeFollowUpListening());
          case MicPhase.preparing:
          case MicPhase.none:
            return _gettingReadyIndicator();
        }
      case VoiceStatus.thinking:
        return const ThinkingAnimation();
      case VoiceStatus.responding:
        return const Icon(Icons.volume_up, color: Aurora.accentGreen, size: 48);
      case VoiceStatus.idle:
        return const SizedBox.shrink();
    }
  }

  Widget _gettingReadyIndicator() => SizedBox(
        key: const Key('getting_ready_hint'),
        height: 56,
        width: 56,
        child: Semantics(
          label: 'Getting ready',
          child: const CircularProgressIndicator(color: Aurora.accentGreen),
        ),
      );

  Widget _tapToTalkButton(VoidCallback onPressed) => IconButton(
        key: const Key('tap_to_talk_button'),
        iconSize: 56,
        icon: const Icon(Icons.mic_none, color: Aurora.accentGreen),
        tooltip: 'Tap to talk',
        onPressed: onPressed,
      );

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
          style: const TextStyle(color: Aurora.textPrimary, fontSize: 18, height: 1.5),
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
            style: const TextStyle(
              color: Aurora.textSecondary,
              fontSize: 16,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        if (state.micPhase == MicPhase.preparing) ...[
          const SizedBox(height: 12),
          const Text(
            'Getting ready…',
            style: TextStyle(color: Aurora.textSecondary),
          ),
        ],
        if (state.micPhase == MicPhase.paused) ...[
          const SizedBox(height: 12),
          const Text(
            'Tap the mic when you’re ready',
            style: TextStyle(color: Aurora.textSecondary),
          ),
        ],
        if (hasTranscript) ...[
          const SizedBox(height: 12),
          Text(
            state.transcript,
            style: const TextStyle(color: Aurora.textPrimary, fontSize: 18, height: 1.5),
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
            // submit() stops the live engine and ships its final transcript;
            // falling back to the last partial only if the engine is already
            // closed. (The text-entry field below uses setThinking directly.)
            onPressed: () => ref.read(voiceProvider.notifier).submit(),
            icon: const Icon(Icons.send),
            label: const Text('Submit'),
          ),
          if (canRetry) ...[
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: () => ref.read(voiceProvider.notifier).startListening(),
              icon: const Icon(Icons.refresh, color: Aurora.textSecondary),
              label: const Text('Re-record', style: TextStyle(color: Aurora.textSecondary)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTextInput() {
    return TextField(
      controller: _textController,
      style: const TextStyle(color: Aurora.textPrimary),
      decoration: InputDecoration(
        hintText: 'Or type here...',
        hintStyle: const TextStyle(color: Aurora.textMuted),
        filled: true,
        fillColor: Aurora.glassFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        suffixIcon: IconButton(
          icon: const Icon(Icons.send, color: Aurora.accentGreen),
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
