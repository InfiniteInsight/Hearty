/// On-disk + download spec for an on-device ASR model. `kind` selects the
/// sherpa `OfflineModelConfig` branch (`'moonshine'` | `'transducer'` |
/// `'nemo-ctc'`); `files` maps logical keys to the filenames inside the dir.
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

/// The selectable on-device transcription models. Parakeet is the default
/// (highest accuracy — the only one that reliably transcribes short symptom
/// words like "bloating"/digits; Moonshine blanked/mis-heard them on-device,
/// D5 2026-06-08). Moonshine stays selectable as the smaller/faster option.
/// Both run through one batch engine — `kind` is the only thing that differs.
enum OnDeviceModel {
  moonshine,
  parakeet,
  // D5 (2026-06-08) candidates: lighter transducer/CTC models trialled to cut
  // Parakeet-0.6b's ~1.36 GB warm RAM while keeping short-word accuracy (the
  // fix is the architecture, not the size). Under evaluation on-device.
  parakeetCtc110m,
  zipformerGigaspeech;

  static const defaultModel = OnDeviceModel.parakeet;

  OnDeviceModelSpec get spec => _specs[this]!;

  String get prefString => name;

  /// Human label for the Settings model picker.
  String get label => switch (this) {
        OnDeviceModel.moonshine => 'Moonshine',
        OnDeviceModel.parakeet => 'Parakeet',
        OnDeviceModel.parakeetCtc110m => 'Parakeet 110m',
        OnDeviceModel.zipformerGigaspeech => 'Zipformer (GigaSpeech)',
      };

  /// One-line trade-off shown under the label in Settings.
  String get blurb => switch (this) {
        OnDeviceModel.moonshine =>
          'Smaller & faster, but misses short words (~${spec.approxMb} MB)',
        OnDeviceModel.parakeet =>
          'Most accurate — recommended (~${spec.approxMb} MB)',
        OnDeviceModel.parakeetCtc110m =>
          'Lighter, near-Parakeet accuracy (~${spec.approxMb} MB)',
        OnDeviceModel.zipformerGigaspeech =>
          'Lightest accurate option (~${spec.approxMb} MB)',
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
  // NeMo FastConformer TDT-CTC 110M (CTC head). Single model file; ~300 MB warm.
  OnDeviceModel.parakeetCtc110m: OnDeviceModelSpec(
    kind: 'nemo-ctc',
    dir: 'asr-parakeet-ctc-110m',
    approxMb: 120,
    downloadUrl: '$_base/'
        'sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000-int8.tar.bz2',
    files: {
      'model': 'model.int8.onnx',
      'tokens': 'tokens.txt',
    },
  ),
  // icefall Zipformer transducer, GigaSpeech. Drop-in to the `transducer` kind.
  OnDeviceModel.zipformerGigaspeech: OnDeviceModelSpec(
    kind: 'transducer',
    dir: 'asr-zipformer-gigaspeech',
    approxMb: 290,
    downloadUrl: '$_base/sherpa-onnx-zipformer-gigaspeech-2023-12-12.tar.bz2',
    files: {
      'encoder': 'encoder-epoch-30-avg-1.int8.onnx',
      'decoder': 'decoder-epoch-30-avg-1.int8.onnx',
      'joiner': 'joiner-epoch-30-avg-1.int8.onnx',
      'tokens': 'tokens.txt',
    },
  ),
};
