/// Decides whether a capture session should use the cloud engine.
/// Pure so the policy is unit-tested; engine construction (which touches
/// `record`/network) is the thin glue in VoiceNotifier._selectEngine.
class SttEngineSelector {
  static bool useCloud({
    required bool online,
    required bool useCloudWhenOnline,
  }) =>
      online && useCloudWhenOnline;
}
