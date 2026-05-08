import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      // Reset any previous state before starting a new upload.
      ref.read(photoProvider.notifier).reset();
      ref
          .read(photoProvider.notifier)
          .uploadAndPoll(widget.file, widget.photoType);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(photoProvider);

    if (state.error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Upload Failed')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              Text(state.error!),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      );
    }

    if (state.statusResponse != null) {
      return PhotoReviewScreen(
        statusResponse: state.statusResponse!,
        photoType: widget.photoType,
      );
    }

    return PhotoProcessingScreen(photoType: widget.photoType);
  }
}
