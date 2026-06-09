/// On-disk + download spec for an on-device ASR model. `kind` selects the
/// sherpa `OfflineModelConfig` branch (`'transducer'` | `'nemo-ctc'`); `files`
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

/// The selectable on-device transcription models.
///
/// Default is **Parakeet-110m** (NeMo FastConformer TDT-CTC): on the D5 device
/// gate (2026-06-09) it matched Parakeet-0.6b accuracy on the short symptom
/// words that broke Moonshine ("bloating"/"nausea"/digits) — with proper
/// casing+punctuation and faster decode — at **~half the warm RAM** (~1.29 GB
/// total PSS vs the 0.6b's ~2.9 GB, which left a 6 GB phone with only ~450 MB
/// free and got the app OOM-reaped). The 0.6b stays selectable as a heavier
/// maximum-accuracy option. (Moonshine — blanked short words — and Zipformer-
/// GigaSpeech — mangled "nausea", all-caps — were trialled and dropped.)
///
/// All models run through one batch engine; `kind` is the only thing that
/// differs (immune-to-short-blank transducer/CTC architectures only).
enum OnDeviceModel {
  parakeetCtc110m,
  parakeet;

  static const defaultModel = OnDeviceModel.parakeetCtc110m;

  OnDeviceModelSpec get spec => _specs[this]!;

  String get prefString => name;

  /// Human label for the Settings model picker.
  String get label => switch (this) {
        OnDeviceModel.parakeetCtc110m => 'Parakeet 110m',
        OnDeviceModel.parakeet => 'Parakeet 0.6B',
      };

  /// One-line trade-off shown under the label in Settings.
  String get blurb => switch (this) {
        OnDeviceModel.parakeetCtc110m =>
          'Recommended — accurate & light (~${spec.approxMb} MB)',
        OnDeviceModel.parakeet =>
          'Maximum accuracy, heavier on memory (~${spec.approxMb} MB)',
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

const _specs = <OnDeviceModel, OnDeviceModelSpec>{
  // NeMo FastConformer TDT-CTC 110M (CTC head). Single model file; ~1.29 GB
  // total PSS warm. Default.
  OnDeviceModel.parakeetCtc110m: OnDeviceModelSpec(
    kind: 'nemo-ctc',
    dir: 'asr-parakeet-ctc-110m',
    approxMb: 126,
    downloadUrl: '$_base/'
        'sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000-int8.tar.bz2',
    files: {
      'model': 'model.int8.onnx',
      'tokens': 'tokens.txt',
    },
  ),
  // NVIDIA Parakeet-TDT-0.6b transducer. Heaviest (~2.9 GB total PSS warm);
  // kept as the maximum-accuracy option.
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
