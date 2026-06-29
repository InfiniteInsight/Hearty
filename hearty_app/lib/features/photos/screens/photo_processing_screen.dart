import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../app/theme/aurora_colors.dart';
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
    return Theme(
      data: AppTheme.aurora,
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: Aurora.background),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  color: Aurora.accentGreen,
                ),
                const SizedBox(height: 24),
                Text(
                  photoType.processingLabel,
                  style: const TextStyle(
                    color: Aurora.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This usually takes 5–10 seconds.',
                  style: TextStyle(color: Aurora.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
