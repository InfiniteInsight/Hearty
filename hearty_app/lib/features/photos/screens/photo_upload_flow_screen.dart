import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/theme/aurora_colors.dart';
import '../models/photo_type.dart';
import '../providers/photo_provider.dart';
import 'photo_processing_screen.dart';
import 'photo_review_screen.dart';

/// A self-contained flow screen that orchestrates photo upload and review.
///
/// On creation it resets [photoProvider] to a clean state, then calls
/// [PhotoNotifier.uploadAndPoll]. While the upload/poll is in progress it
/// shows [PhotoProcessingScreen]; once a result arrives it shows
/// [PhotoReviewScreen]; on error it shows a simple error UI with a back button.
class PhotoUploadFlowScreen extends ConsumerStatefulWidget {
  final File file;
  final PhotoType photoType;

  const PhotoUploadFlowScreen({
    super.key,
    required this.file,
    required this.photoType,
  });

  @override
  ConsumerState<PhotoUploadFlowScreen> createState() =>
      _PhotoUploadFlowScreenState();
}

class _PhotoUploadFlowScreenState extends ConsumerState<PhotoUploadFlowScreen> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      // Kick off the upload AFTER the first frame: mutating photoProvider
      // synchronously here (during build) throws "modify a provider while the
      // widget tree was building" on device, leaving the screen stuck on
      // "Analyzing food".
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Reset any previous state before starting a new upload.
        ref.read(photoProvider.notifier).reset();
        ref
            .read(photoProvider.notifier)
            .uploadAndPoll(widget.file, widget.photoType);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(photoProvider);

    final analysis = state.analysis;

    // Transport/timeout error (no analysis came back) OR a backend 'failed'
    // status. Both surface an inline message plus retry + manual fallback.
    final failureMessage = state.error ??
        (analysis != null && analysis.isFailed
            ? (analysis.error ?? 'We could not analyze this photo.')
            : null);

    if (failureMessage != null) {
      return Theme(
        data: AppTheme.aurora,
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: Aurora.background),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(title: const Text('Analysis Failed')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Aurora.accentRed,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      failureMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Aurora.accentRed),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () =>
                          ref.read(photoProvider.notifier).retry(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Aurora.accentGreen,
                        foregroundColor: const Color(0xFF052E20),
                      ),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      // Manual-entry fallback: return to the logging screen so
                      // the user can type the meal instead.
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: Aurora.accentGreen,
                      ),
                      child: const Text('Enter manually'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (analysis != null && analysis.isComplete) {
      return PhotoReviewScreen(
        analysis: analysis,
        photoType: widget.photoType,
      );
    }

    return PhotoProcessingScreen(photoType: widget.photoType);
  }
}
