import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../hearty_api_client.dart';
import '../models/trends_data.dart';

class TrendsNotifier extends AsyncNotifier<TrendsData> {
  int _days = 30;

  @override
  Future<TrendsData> build() async {
    final client = ref.read(heartyApiClientProvider);
    return client.fetchTrends(days: _days);
  }

  Future<void> setDays(int days) async {
    _days = days;
    final client = ref.read(heartyApiClientProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => client.fetchTrends(days: _days));
  }
}

final trendsProvider =
    AsyncNotifierProvider<TrendsNotifier, TrendsData>(TrendsNotifier.new);
