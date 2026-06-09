import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/stt/on_device_model.dart';

void main() {
  group('OnDeviceModel registry', () {
    test('parakeet-110m is the default', () {
      expect(OnDeviceModel.defaultModel, OnDeviceModel.parakeetCtc110m);
    });

    test('parakeet-110m resolves to a nemo-ctc spec with its files', () {
      final s = OnDeviceModel.parakeetCtc110m.spec;
      expect(s.kind, 'nemo-ctc');
      expect(s.dir, isNotEmpty);
      expect(s.files.keys, containsAll(['model', 'tokens']));
      expect(s.downloadUrl, contains('110m'));
      expect(s.approxMb, greaterThan(0));
    });

    test('parakeet 0.6b resolves to a transducer-kind spec with its files', () {
      final s = OnDeviceModel.parakeet.spec;
      expect(s.kind, 'transducer');
      expect(s.files.keys, containsAll(['encoder', 'decoder', 'joiner', 'tokens']));
      expect(s.downloadUrl, contains('parakeet'));
      expect(s.approxMb, greaterThan(0));
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
