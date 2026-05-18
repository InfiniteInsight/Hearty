// lib/core/api/providers/voice_queue_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../offline/local_voice_queue_dao.dart';
import '../../offline/offline_database.dart';

class VoiceQueueNotifier
    extends StreamNotifier<List<LocalVoiceQueueData>> {
  @override
  Stream<List<LocalVoiceQueueData>> build() {
    return ref.watch(localVoiceQueueDaoProvider).watchPending();
  }
}

final voiceQueueProvider =
    StreamNotifierProvider<VoiceQueueNotifier, List<LocalVoiceQueueData>>(
        VoiceQueueNotifier.new);
