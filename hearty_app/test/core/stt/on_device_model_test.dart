import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/stt/on_device_model.dart';

void main() {
  group('OnDeviceModel registry', () {
    test('parakeet is the default', () {
      expect(OnDeviceModel.defaultModel, OnDeviceModel.parakeet);
    });

    test('moonshine resolves to a moonshine-kind spec with its files', () {
      final s = OnDeviceModel.moonshine.spec;
      expect(s.kind, 'moonshine');
      expect(s.dir, isNotEmpty);
      expect(s.files.keys,
          containsAll(['preprocessor', 'encoder', 'uncachedDecoder', 'cachedDecoder', 'tokens']));
      expect(s.downloadUrl, contains('moonshine'));
      expect(s.approxMb, greaterThan(0));
    });

    test('parakeet resolves to a transducer-kind spec with its files', () {
      final s = OnDeviceModel.parakeet.spec;
      expect(s.kind, 'transducer');
      expect(s.files.keys, containsAll(['encoder', 'decoder', 'joiner', 'tokens']));
      expect(s.downloadUrl, contains('parakeet'));
      expect(s.approxMb, greaterThan(s == OnDeviceModel.moonshine.spec ? 0 : 0));
    });

    test('pref string round-trips; unknown falls back to the default', () {
      for (final m in OnDeviceModel.values) {
        expect(OnDeviceModel.fromPrefString(m.prefString), m);
      }
      expect(OnDeviceModel.fromPrefString('nonsense'), OnDeviceModel.defaultModel);
      expect(OnDeviceModel.fromPrefString(null), OnDeviceModel.defaultModel);
    });
  });
}
