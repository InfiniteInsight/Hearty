import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/stt/stt_engine_selector.dart';

void main() {
  group('SttEngineSelector.useCloud', () {
    test('cloud only when online AND the setting is on', () {
      expect(SttEngineSelector.useCloud(online: true, useCloudWhenOnline: true),
          isTrue);
      expect(SttEngineSelector.useCloud(online: true, useCloudWhenOnline: false),
          isFalse); // user prefers on-device
      expect(SttEngineSelector.useCloud(online: false, useCloudWhenOnline: true),
          isFalse); // offline → on-device
      expect(
          SttEngineSelector.useCloud(online: false, useCloudWhenOnline: false),
          isFalse);
    });
  });
}
