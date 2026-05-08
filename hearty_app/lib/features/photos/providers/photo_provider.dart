import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/hearty_api_client.dart';
import '../models/photo_status_response.dart';
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
  final PhotoStatusResponse? statusResponse;
  final String? error;

  const PhotoState({
    this.isUploading = false,
    this.isPolling = false,
    this.photoId,
    this.photoType,
    this.statusResponse,
    this.error,
  });

  PhotoState copyWith({
    bool? isUploading,
    bool? isPolling,
    Object? photoId = _sentinel,
    Object? photoType = _sentinel,
    Object? statusResponse = _sentinel,
    Object? error = _sentinel,
  }) {
    return PhotoState(
      isUploading: isUploading ?? this.isUploading,
      isPolling: isPolling ?? this.isPolling,
      photoId: identical(photoId, _sentinel) ? this.photoId : photoId as String?,
      photoType: identical(photoType, _sentinel)
          ? this.photoType
          : photoType as PhotoType?,
      statusResponse: identical(statusResponse, _sentinel)
          ? this.statusResponse
          : statusResponse as PhotoStatusResponse?,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class PhotoNotifier extends StateNotifier<PhotoState> {
  PhotoNotifier(this._api) : super(const PhotoState());

  final HeartyApiClient _api;

  /// Uploads [file] and starts polling for processing results.
  Future<void> uploadAndPoll(File file, PhotoType type) async {
    state = state.copyWith(
      isUploading: true,
      error: null,
      statusResponse: null,
    );
    try {
      final uploadResp = await _api.uploadPhoto(
        file: file,
        photoType: type.apiValue,
      );
      state = state.copyWith(
        isUploading: false,
        isPolling: true,
        photoId: uploadResp.id,
        photoType: type,
      );
      await _poll(uploadResp.id);
    } catch (e) {
      state = state.copyWith(
        isUploading: false,
        isPolling: false,
        error: e.toString(),
      );
    }
  }

  Future<void> _poll(String photoId) async {
    // Poll every 2 seconds, up to 30 seconds (15 attempts).
    for (int i = 0; i < 15; i++) {
      await Future.delayed(const Duration(seconds: 2));
      try {
        final status = await _api.fetchPhotoStatus(photoId);
        if (status.status == 'complete' || status.status == 'error') {
          state = state.copyWith(isPolling: false, statusResponse: status);
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
