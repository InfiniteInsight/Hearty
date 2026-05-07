import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../wake_word_channel.dart';

final wakeWordDetectedProvider =
    StateNotifierProvider<WakeWordNotifier, bool>((ref) {
  return WakeWordNotifier()..init();
});

class WakeWordNotifier extends StateNotifier<bool> {
  WakeWordNotifier() : super(false);

  void init() {
    WakeWordChannel.onWakeWordDetected(() => setDetected(true));
  }

  void setDetected(bool value) => state = value;

  @override
  void dispose() {
    WakeWordChannel.clearHandler();
    super.dispose();
  }
}
