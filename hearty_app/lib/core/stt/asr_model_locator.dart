import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// On-disk paths to a sherpa streaming transducer model.
class AsrModelPaths {
  const AsrModelPaths(this.encoder, this.decoder, this.joiner, this.tokens);
  final String encoder, decoder, joiner, tokens;
}

/// Resolves the on-device streaming ASR model directory.
///
/// Phase B expects the model present at `<externalFiles>/asr-model` (pushed via
/// adb during dev). Plan D adds first-run download/caching. Returns null if any
/// required file is missing so the caller can fall back to text entry.
class AsrModelLocator {
  static const dirName = 'asr-model';

  static Future<AsrModelPaths?> resolve() async {
    final ext = await getExternalStorageDirectory();
    if (ext == null) return null;
    final dir = '${ext.path}/$dirName';
    final p = AsrModelPaths(
      '$dir/encoder.int8.onnx',
      '$dir/decoder.int8.onnx',
      '$dir/joiner.int8.onnx',
      '$dir/tokens.txt',
    );
    for (final f in [p.encoder, p.decoder, p.joiner, p.tokens]) {
      if (!File(f).existsSync()) return null;
    }
    return p;
  }
}
