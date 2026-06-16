import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/hearty_api_client.dart';
import '../../../core/api/models/photo_analysis.dart';
import '../models/photo_type.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

// Sentinel used to distinguish "explicit null" from "not provided" in copyWith.
const _sentinel = Object();

class PhotoState {
  final bool isUploading;
  final bool isPolling;
  final String? photoId;
  final PhotoType? photoType;
  final PhotoAnalysis? analysis;
  final String? error;

  const PhotoState({
    this.isUploading = false,
    this.isPolling = false,
    this.photoId,
    this.photoType,
    this.analysis,
    this.error,
  });

  PhotoState copyWith({
    bool? isUploading,
    bool? isPolling,
    Object? photoId = _sentinel,
    Object? photoType = _sentinel,
    Object? analysis = _sentinel,
    Object? error = _sentinel,
  }) {
    return PhotoState(
      isUploading: isUploading ?? this.isUploading,
      isPolling: isPolling ?? this.isPolling,
      photoId: identical(photoId, _sentinel) ? this.photoId : photoId as String?,
      photoType: identical(photoType, _sentinel)
          ? this.photoType
          : photoType as PhotoType?,
      analysis: identical(analysis, _sentinel)
          ? this.analysis
          : analysis as PhotoAnalysis?,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class PhotoNotifier extends StateNotifier<PhotoState> {
  PhotoNotifier(
    this._api, {
    // Overridable in tests so the poll loop can run without a real 2s wait.
    this.pollInterval = const Duration(seconds: 2),
  }) : super(const PhotoState());

  final HeartyApiClient _api;
  final Duration pollInterval;

  /// Uploads [file] and starts polling for processing results.
  Future<void> uploadAndPoll(File file, PhotoType type) async {
    state = state.copyWith(
      isUploading: true,
      error: null,
      analysis: null,
    );
    try {
      final String photoId;
      if (type == PhotoType.foodPlate) {
        // AI Vision food-plate path (Spec 06): bytes-based food upload.
        photoId = await _api.uploadFoodPhoto(
          bytes: await file.readAsBytes(),
          filename: file.uri.pathSegments.last,
          type: type.apiValue,
        );
      } else {
        // Other photo types (barcode / labels) keep the File-based upload.
        final uploadResp = await _api.uploadPhoto(
          file: file,
          photoType: type.apiValue,
        );
        photoId = uploadResp.id;
      }
      state = state.copyWith(
        isUploading: false,
        isPolling: true,
        photoId: photoId,
        photoType: type,
      );
      await _poll(photoId);
    } catch (e) {
      state = state.copyWith(
        isUploading: false,
        isPolling: false,
        error: e.toString(),
      );
    }
  }

  /// Re-enqueues a failed photo and resumes polling.
  Future<void> retry() async {
    final photoId = state.photoId;
    if (photoId == null) return;
    state = state.copyWith(isPolling: true, analysis: null, error: null);
    try {
      await _api.retryPhoto(photoId);
      await _poll(photoId);
    } catch (e) {
      state = state.copyWith(isPolling: false, error: e.toString());
    }
  }

  Future<void> _poll(String photoId) async {
    // Poll every 2 seconds, up to 30 seconds (15 attempts).
    for (int i = 0; i < 15; i++) {
      await Future.delayed(pollInterval);
      try {
        final analysis = await _api.fetchPhotoStatus(photoId);
        // Backend terminal statuses are 'complete' and 'failed'.
        if (analysis.isComplete || analysis.isFailed) {
          state = state.copyWith(isPolling: false, analysis: analysis);
          return;
        }
      } catch (_) {
        // Keep polling on transient errors.
      }
    }
    // Timed out.
    state = state.copyWith(
      isPolling: false,
      error: 'Processing timed out. Please try again.',
    );
  }

  void reset() => state = const PhotoState();
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final photoProvider =
    StateNotifierProvider<PhotoNotifier, PhotoState>((ref) {
  return PhotoNotifier(ref.watch(heartyApiClientProvider));
});
