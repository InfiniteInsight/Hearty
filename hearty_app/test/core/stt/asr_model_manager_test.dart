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
      expect(await mgr.isReady(OnDeviceModel.parakeetCtc110m), isFalse);
      expect(await mgr.resolvePaths(OnDeviceModel.parakeetCtc110m.spec), isNull);
    });

    test('resolvePaths returns all files once present', () async {
      writeFiles(OnDeviceModel.parakeetCtc110m);
      final paths = await mgr.resolvePaths(OnDeviceModel.parakeetCtc110m.spec);
      expect(paths, isNotNull);
      expect(paths!.keys, containsAll(OnDeviceModel.parakeetCtc110m.spec.files.keys));
      expect(await mgr.isReady(OnDeviceModel.parakeetCtc110m), isTrue);
    });

    test('a partial model is not ready (one file missing)', () async {
      writeFiles(OnDeviceModel.parakeet, only: ['encoder', 'decoder', 'tokens']);
      // joiner missing
      expect(await mgr.isReady(OnDeviceModel.parakeet), isFalse);
    });

    test('models resolve independently', () async {
      writeFiles(OnDeviceModel.parakeetCtc110m);
      expect(await mgr.isReady(OnDeviceModel.parakeetCtc110m), isTrue);
      expect(await mgr.isReady(OnDeviceModel.parakeet), isFalse);
    });

    test('concurrent ensureAndWarm for one model coalesces into one op',
        () async {
      // Files present → no download; both calls must share ONE in-flight op so
      // repeated mic taps don't spawn racing downloads/isolates. (Warming the
      // recognizer itself fails in the test host — no native lib — which is
      // fine: we only assert coalescing, then settle the shared error.)
      writeFiles(OnDeviceModel.parakeetCtc110m);
      final f1 = mgr.ensureAndWarm(OnDeviceModel.parakeetCtc110m);
      final f2 = mgr.ensureAndWarm(OnDeviceModel.parakeetCtc110m);
      expect(identical(f1, f2), isTrue);
      await f1.catchError((_) {});
      await f2.catchError((_) {});
      await mgr.dispose();
    });
  });
}
