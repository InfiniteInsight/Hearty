/// On-disk + download spec for an on-device ASR model. `kind` selects the
/// sherpa `OfflineModelConfig` branch (`'moonshine'` | `'transducer'`); `files`
/// maps logical keys to the filenames inside the model dir.
class OnDeviceModelSpec {
  const OnDeviceModelSpec({
    required this.kind,
    required this.dir,
    required this.files,
    required this.downloadUrl,
    required this.approxMb,
  });

  final String kind;
  final String dir; // under <externalFiles>
  final Map<String, String> files;
  final String downloadUrl; // sherpa-onnx release .tar.bz2
  final int approxMb;
}

/// The selectable on-device transcription models. Moonshine is the default
/// (small, fast to load); Parakeet is the higher-accuracy, heavier option.
/// Both run through one batch engine — `kind` is the only thing that differs.
enum OnDeviceModel {
  moonshine,
  parakeet;

  static const defaultModel = OnDeviceModel.moonshine;

  OnDeviceModelSpec get spec => _specs[this]!;

  String get prefString => name;

  /// Human label for the Settings model picker.
  String get label => switch (this) {
        OnDeviceModel.moonshine => 'Moonshine',
        OnDeviceModel.parakeet => 'Parakeet',
      };

  /// One-line trade-off shown under the label in Settings.
  String get blurb => switch (this) {
        OnDeviceModel.moonshine =>
          'Smaller & faster — recommended (~${spec.approxMb} MB)',
        OnDeviceModel.parakeet =>
          'Larger, most accurate (~${spec.approxMb} MB download)',
      };

  static OnDeviceModel fromPrefString(String? s) {
    for (final m in values) {
      if (m.name == s) return m;
    }
    return defaultModel;
  }
}

const _base =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models';

// Filenames verified against the pushed spike models.
const _specs = <OnDeviceModel, OnDeviceModelSpec>{
  OnDeviceModel.moonshine: OnDeviceModelSpec(
    kind: 'moonshine',
    dir: 'asr-moonshine-base',
    approxMb: 275,
    downloadUrl: '$_base/sherpa-onnx-moonshine-base-en-int8.tar.bz2',
    files: {
      'preprocessor': 'preprocess.onnx',
      'encoder': 'encode.int8.onnx',
      'uncachedDecoder': 'uncached_decode.int8.onnx',
      'cachedDecoder': 'cached_decode.int8.onnx',
      'tokens': 'tokens.txt',
    },
  ),
  OnDeviceModel.parakeet: OnDeviceModelSpec(
    kind: 'transducer',
    dir: 'asr-parakeet-tdt',
    approxMb: 631,
    downloadUrl:
        '$_base/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8.tar.bz2',
    files: {
      'encoder': 'encoder.int8.onnx',
      'decoder': 'decoder.int8.onnx',
      'joiner': 'joiner.int8.onnx',
      'tokens': 'tokens.txt',
    },
  ),
};
