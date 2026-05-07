import 'package:just_audio/just_audio.dart';

/// Plays the wake word detection chime once.
class ChimePlayer {
  ChimePlayer._();

  static final ChimePlayer instance = ChimePlayer._();

  final _player = AudioPlayer();
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await _player.setAsset('assets/audio/wake_chime.wav');
      _initialized = true;
    }
  }

  Future<void> play() async {
    await _ensureInitialized();
    await _player.seek(Duration.zero);
    await _player.play();
  }

  Future<void> dispose() => _player.dispose();
}
