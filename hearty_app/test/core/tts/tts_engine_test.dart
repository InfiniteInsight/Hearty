import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:hearty_app/core/tts/system_tts_engine.dart';

class _FakeFlutterTts extends Fake implements FlutterTts {
  String? spokenText;
  VoidCallback? completion;
  bool stopped = false;

  @override
  Future<dynamic> setLanguage(String? l) async => 1;
  @override
  Future<dynamic> setSpeechRate(double? r) async => 1;
  @override
  Future<dynamic> setPitch(double? p) async => 1;
  @override
  Future<dynamic> setVoice(Map<String, String> v) async => 1;
  @override
  Future<dynamic> speak(String t, {bool focus = false}) async {
    spokenText = t;
    completion?.call();
    return 1;
  }
  @override
  Future<dynamic> stop() async {
    stopped = true;
    return 1;
  }
  @override
  void setCompletionHandler(VoidCallback c) {
    completion = c;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SystemTtsEngine speaks text and fires completion', () async {
    final fake = _FakeFlutterTts();
    final engine = SystemTtsEngine(ttsForTesting: fake);
    var done = false;
    engine.setCompletionHandler(() => done = true);
    await engine.init();
    await engine.speak('hello');
    expect(fake.spokenText, 'hello');
    expect(done, true);
  });

  test('SystemTtsEngine.init returns true and stop() delegates', () async {
    final fake = _FakeFlutterTts();
    final engine = SystemTtsEngine(ttsForTesting: fake);
    final ok = await engine.init();
    expect(ok, true);
    await engine.stop();
    expect(fake.stopped, true);
  });
}
