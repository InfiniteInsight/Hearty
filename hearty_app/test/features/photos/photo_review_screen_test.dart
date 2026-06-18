import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/api/hearty_api_client.dart';
import 'package:hearty_app/core/api/models/photo_analysis.dart';
import 'package:hearty_app/features/photos/models/photo_type.dart';
import 'package:hearty_app/features/photos/models/photo_upload_response.dart';
import 'package:hearty_app/features/photos/providers/photo_provider.dart';
import 'package:hearty_app/features/photos/screens/photo_review_screen.dart';
import 'package:hearty_app/features/photos/screens/photo_upload_flow_screen.dart';

/// Fake client driving the photo flow through an overridden
/// [heartyApiClientProvider] (mirrors the trends widget-test harness).
class FakeHeartyApiClient implements HeartyApiClient {
  FakeHeartyApiClient(this._status);

  final PhotoAnalysis _status;
  int retryCalls = 0;

  @override
  Future<String> uploadFoodPhoto({
    required List<int> bytes,
    required String filename,
    String type = 'food_plate',
    String? mealId,
  }) async =>
      'photo-1';

  @override
  Future<PhotoUploadResponse> uploadPhoto({
    required File file,
    required String photoType,
  }) async =>
      const PhotoUploadResponse(
        id: 'photo-1',
        type: 'barcode',
        status: 'processing',
        message: '',
      );

  @override
  Future<PhotoAnalysis> fetchPhotoStatus(String photoId) async => _status;

  @override
  Future<void> retryPhoto(String photoId) async {
    retryCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A [PhotoNotifier] pre-seeded into a fixed state. [uploadAndPoll] is a no-op
/// so the flow screen's didChangeDependencies doesn't overwrite the seed; only
/// [retry] is observed.
class _FakePhotoNotifier extends PhotoNotifier {
  _FakePhotoNotifier(PhotoState seed) : super(FakeHeartyApiClient(_dummy)) {
    state = seed;
  }

  static const _dummy = PhotoAnalysis(id: '', type: 'food_plate', status: '');

  int retryCalls = 0;

  @override
  Future<void> uploadAndPoll(File file, PhotoType type) async {}

  @override
  void reset() {}

  @override
  Future<void> retry() async {
    retryCalls++;
  }
}

void main() {
  group('PhotoReviewScreen (complete)', () {
    testWidgets('renders identified food names and portions', (tester) async {
      const analysis = PhotoAnalysis(
        id: 'photo-1',
        type: 'food_plate',
        status: 'complete',
        foods: [
          IdentifiedFood(
            name: 'Grilled salmon',
            portion: 'approximately 1 fillet',
            confidence: 0.82,
          ),
          IdentifiedFood(name: 'Side salad', confidence: 0.4),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: PhotoReviewScreen(
              analysis: analysis,
              photoType: PhotoType.foodPlate,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Detected Foods'), findsOneWidget);
      expect(find.text('Grilled salmon'), findsOneWidget);
      expect(find.text('approximately 1 fillet'), findsOneWidget);
      expect(find.text('Side salad'), findsOneWidget);
      expect(find.text('82% confidence'), findsOneWidget);
    });
  });

  group('PhotoUploadFlowScreen (failed)', () {
    testWidgets('shows the backend error plus retry + manual fallback',
        (tester) async {
      // Override photoProvider with a notifier seeded straight into the failed
      // state, so the flow screen's failure-branch rendering is what's tested
      // (the real upload/poll timing + file IO is device-verified separately).
      final notifier = _FakePhotoNotifier(
        const PhotoState(
          photoId: 'photo-1',
          analysis: PhotoAnalysis(
            id: 'photo-1',
            type: 'food_plate',
            status: 'failed',
            error: 'Vision model unavailable',
          ),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [photoProvider.overrideWith((ref) => notifier)],
          child: MaterialApp(
            home: PhotoUploadFlowScreen(
              file: File('ignored-by-fake-notifier.jpg'),
              photoType: PhotoType.foodPlate,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Vision model unavailable'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Enter manually'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(notifier.retryCalls, 1);
    });
  });

  group('PhotoNotifier poll termination', () {
    // Drives the REAL uploadAndPoll -> _poll loop (the load-bearing fix:
    // terminate on backend status 'failed', formerly the stale 'error').
    // Uses PhotoType.barcode so the File-based uploadPhoto path runs (no
    // readAsBytes file IO) and a ~zero poll interval so no real wait is needed.
    test('stores analysis and stops polling when status is failed', () async {
      final api = FakeHeartyApiClient(const PhotoAnalysis(
        id: 'photo-1',
        type: 'barcode',
        status: 'failed',
        error: 'boom',
      ));
      final notifier =
          PhotoNotifier(api, pollInterval: const Duration(milliseconds: 1));
      addTearDown(notifier.dispose);

      await notifier.uploadAndPoll(
        File('unused-barcode-path.jpg'),
        PhotoType.barcode,
      );

      expect(notifier.state.isPolling, isFalse);
      expect(notifier.state.analysis, isNotNull);
      expect(notifier.state.analysis!.isFailed, isTrue);
      expect(notifier.state.analysis!.error, 'boom');
      // The generic timeout error must NOT be set — the loop terminated on the
      // 'failed' status, not by running out of attempts.
      expect(notifier.state.error, isNull);
    });

    test('stores analysis when status is complete', () async {
      final api = FakeHeartyApiClient(const PhotoAnalysis(
        id: 'photo-1',
        type: 'barcode',
        status: 'complete',
        foods: [IdentifiedFood(name: 'apple')],
      ));
      final notifier =
          PhotoNotifier(api, pollInterval: const Duration(milliseconds: 1));
      addTearDown(notifier.dispose);

      await notifier.uploadAndPoll(
        File('unused-barcode-path.jpg'),
        PhotoType.barcode,
      );

      expect(notifier.state.isPolling, isFalse);
      expect(notifier.state.analysis!.isComplete, isTrue);
      expect(notifier.state.error, isNull);
    });
  });
}
