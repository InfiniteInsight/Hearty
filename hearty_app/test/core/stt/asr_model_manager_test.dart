import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/stt/asr_model_manager.dart';
import 'package:hearty_app/core/stt/on_device_model.dart';

void main() {
  group('AsrModelManager path resolution', () {
    late Directory tmp;
    late AsrModelManager mgr;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('asr-mgr-test');
      mgr = AsrModelManager(externalDir: () async => tmp.path);
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    void writeFiles(OnDeviceModel m, {Iterable<String>? only}) {
      final spec = m.spec;
      final dir = Directory('${tmp.path}/${spec.dir}')
        ..createSync(recursive: true);
      for (final e in spec.files.entries) {
        if (only != null && !only.contains(e.key)) continue;
        File('${dir.path}/${e.value}').writeAsStringSync('x');
      }
    }

    test('isReady is false when nothing is downloaded', () async {
      expect(await mgr.isReady(OnDeviceModel.moonshine), isFalse);
      expect(await mgr.resolvePaths(OnDeviceModel.moonshine.spec), isNull);
    });

    test('resolvePaths returns all files once present', () async {
      writeFiles(OnDeviceModel.moonshine);
      final paths = await mgr.resolvePaths(OnDeviceModel.moonshine.spec);
      expect(paths, isNotNull);
      expect(paths!.keys, containsAll(OnDeviceModel.moonshine.spec.files.keys));
      expect(await mgr.isReady(OnDeviceModel.moonshine), isTrue);
    });

    test('a partial model is not ready (one file missing)', () async {
      writeFiles(OnDeviceModel.parakeet, only: ['encoder', 'decoder', 'tokens']);
      // joiner missing
      expect(await mgr.isReady(OnDeviceModel.parakeet), isFalse);
    });

    test('models resolve independently', () async {
      writeFiles(OnDeviceModel.moonshine);
      expect(await mgr.isReady(OnDeviceModel.moonshine), isTrue);
      expect(await mgr.isReady(OnDeviceModel.parakeet), isFalse);
    });
  });
}
