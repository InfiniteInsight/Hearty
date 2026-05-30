import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:hearty_app/core/tts/neural_tts_engine.dart';
import 'package:hearty_app/core/tts/system_tts_engine.dart';
import 'package:hearty_app/core/tts/tts_engine.dart';
import 'package:hearty_app/core/tts/tts_engine_factory.dart';

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

  test('NeuralTtsEngine.init returns false when model dir is missing', () async {
    final engine = NeuralTtsEngine(modelAssetDir: 'assets/tts/does-not-exist');
    final ok = await engine.init();
    expect(ok, false);
  });

  group('createTtsEngine', () {
    test('falls back to system engine when neural init returns false', () async {
      final engine = await createTtsEngine(
        neuralBuilder: () => _StubEngine(initResult: false, tag: 'neural'),
        systemBuilder: () => _StubEngine(initResult: true, tag: 'system'),
      );
      expect((engine as _StubEngine).tag, 'system');
    });

    test('uses neural engine when its init succeeds', () async {
      final engine = await createTtsEngine(
        neuralBuilder: () => _StubEngine(initResult: true, tag: 'neural'),
        systemBuilder: () => _StubEngine(initResult: true, tag: 'system'),
      );
      expect((engine as _StubEngine).tag, 'neural');
    });

    test('uses system engine directly when a system voice override is set', () async {
      String? initedWith;
      final engine = await createTtsEngine(
        systemVoiceOverride: 'en-us-x-iol-local',
        neuralBuilder: () => _StubEngine(initResult: true, tag: 'neural'),
        systemBuilder: () => _StubEngine(
            initResult: true, tag: 'system', onInit: (v) => initedWith = v),
      );
      expect((engine as _StubEngine).tag, 'system');
      expect(initedWith, 'en-us-x-iol-local');
    });
  });
}

class _StubEngine implements TtsEngine {
  _StubEngine({required this.initResult, required this.tag, this.onInit});
  final bool initResult;
  final String tag;
  final void Function(String? voiceName)? onInit;

  @override
  Future<bool> init({String? voiceName}) async {
    onInit?.call(voiceName);
    return initResult;
  }

  @override
  Future<void> speak(String text) async {}

  @override
  Future<void> stop() async {}

  @override
  void setCompletionHandler(VoidCallback onDone) {}

  @override
  Future<void> setStyle(TtsStyle style) async {}

  @override
  Future<void> dispose() async {}
}
