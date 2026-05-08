import 'package:flutter/material.dart';

import '../models/photo_type.dart';

/// Full-screen loading screen shown while a photo is being uploaded and
/// processed by the server.
///
/// This is a plain [StatelessWidget] — it does not connect to Riverpod.
/// The parent screen watches [photoProvider] and navigates away once
/// [PhotoState.statusResponse] becomes non-null.
class PhotoProcessingScreen extends StatelessWidget {
  const PhotoProcessingScreen({super.key, required this.photoType});

  final PhotoType photoType;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(photoType.processingLabel),
            const SizedBox(height: 8),
            Text(
              'This usually takes 5–10 seconds.',
              style: textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
