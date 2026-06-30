import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/hearty_api_client.dart';
import '../../../core/api/models/checkin_gap.dart';
import '../../../core/api/providers/preferences_provider.dart';

/// Today's outstanding check-in gaps, fetched on demand for the home banner.
/// autoDispose so it re-runs when the home screen is revisited (e.g. after the
/// user resolves gaps via /checkin and pops back).
final checkinGapsTodayProvider =
    FutureProvider.autoDispose<CheckinGapsResult>((ref) {
  return ref.read(heartyApiClientProvider).fetchCheckinGaps(DateTime.now());
});

/// Today as `YYYY-MM-DD` in local time — matches the router's today-helper
/// format so the pushed /checkin route reviews the same day.
String _todayYmd() {
  final d = DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// A tappable "Review my day" banner shown on the home screen ONLY when the
/// daily check-in is enabled AND there is something to review (non-empty,
/// non-expired gaps). While loading or on error/empty it renders nothing.
class HomeCheckinBanner extends ConsumerWidget {
  const HomeCheckinBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Don't flash before prefs resolve: default to disabled when unloaded.
    final enabled = ref.watch(preferencesProvider).valueOrNull?.dailyCheckinEnabled ?? false;
    if (!enabled) return const SizedBox.shrink();

    final gaps = ref.watch(checkinGapsTodayProvider).valueOrNull;
    if (gaps == null || gaps.expired || gaps.gaps.isEmpty) {
      return const SizedBox.shrink();
    }

    return CheckinBannerView(
      key: const Key('home-checkin-banner'),
      count: gaps.gaps.length,
      onTap: () async {
        // Refresh the gap count on return so answered/dismissed gaps drop off
        // (and the banner hides when nothing's left).
        await context.push('/checkin?date=${_todayYmd()}');
        ref.invalidate(checkinGapsTodayProvider);
      },
    );
  }
}

/// Pure presentation of the banner — takes a [count] and [onTap] so it can be
/// widget-tested in isolation without a ProviderScope.
class CheckinBannerView extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const CheckinBannerView({
    super.key,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        color: scheme.primaryContainer,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.checklist_rounded,
                color: scheme.onPrimaryContainer, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                count == 1
                    ? 'Review my day — 1 thing to check'
                    : 'Review my day — $count things to check',
                style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 13),
              ),
            ),
            Icon(Icons.chevron_right, color: scheme.onPrimaryContainer, size: 18),
          ],
        ),
      ),
    );
  }
}
