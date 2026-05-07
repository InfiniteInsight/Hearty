import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/models/meal_log.dart';
import '../../../core/api/offline_exception.dart';
import '../../../core/api/providers/meals_provider.dart';
import '../../voice/providers/voice_provider.dart';
import '../../voice/screens/voice_overlay_screen.dart';

// ---------------------------------------------------------------------------
// Main screen
// ---------------------------------------------------------------------------

class LogEntryScreen extends ConsumerStatefulWidget {
  const LogEntryScreen({super.key});

  @override
  ConsumerState<LogEntryScreen> createState() => _LogEntryScreenState();
}

class _LogEntryScreenState extends ConsumerState<LogEntryScreen>
    with SingleTickerProviderStateMixin {
  final _textController = TextEditingController();
  bool _isLoading = false;
  MealLog? _reviewMeal;

  // Animation controller for the pulsing voice button while listening.
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _openVoiceOverlay() async {
    ref.read(voiceProvider.notifier).startListening();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const VoiceOverlayScreen(),
    );
  }

  Future<void> _submitText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    setState(() {
      _isLoading = true;
      _reviewMeal = null;
    });
    _textController.clear();

    try {
      await ref.read(mealsProvider.notifier).logMeal(trimmed);
      if (!mounted) return;

      final mealsState = ref.read(mealsProvider);
      if (mealsState.hasError) {
        final err = mealsState.error;
        final msg = err is OfflineException
            ? err.message
            : 'Failed to log meal — please try again';
        _showError(msg);
        return;
      }

      final logged = mealsState.valueOrNull?.firstOrNull;
      if (logged == null) {
        _showError('Failed to log meal — please try again');
        return;
      }

      setState(() {
        _reviewMeal = logged;
        _isLoading = false;
      });
    } on OfflineException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to log meal — please try again');
    }
  }

  void _showError(String message) {
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _dismissReviewCard() {
    setState(() => _reviewMeal = null);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final voiceState = ref.watch(voiceProvider);
    final isListening = voiceState.status.name == 'listening' ||
        voiceState.status.name == 'awaitingFollowUp';

    final mealsAsync = ref.watch(mealsProvider);
    final recentChipLabels = _buildChipLabels(mealsAsync.valueOrNull ?? []);

    return Scaffold(
      appBar: AppBar(title: const Text('Log Entry')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),

            // ── Voice button ──────────────────────────────────────────────
            Center(
              child: GestureDetector(
                onTap: _openVoiceOverlay,
                child: isListening
                    ? ScaleTransition(
                        scale: _pulseAnimation,
                        child: _VoiceButton(isListening: true),
                      )
                    : const _VoiceButton(isListening: false),
              ),
            ),

            const SizedBox(height: 24),

            // ── Text input + camera button ────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: InputDecoration(
                      hintText: 'Or type what you ate...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: () => _submitText(_textController.text),
                      ),
                    ),
                    onSubmitted: _submitText,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.camera_alt),
                  tooltip: 'Log with camera',
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Camera logging — coming in a future update'),
                      ),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ── Recent meals chips ────────────────────────────────────────
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: recentChipLabels
                  .map(
                    (label) => ActionChip(
                      label: Text(label),
                      onPressed: () => _submitText(label),
                    ),
                  )
                  .toList(),
            ),

            const SizedBox(height: 24),

            // ── Review area (loading / card) ──────────────────────────────
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_reviewMeal != null)
              _ReviewCard(
                meal: _reviewMeal!,
                onLog: () => context.pop(),
                onEdit: _dismissReviewCard,
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Chip label helpers
  // ---------------------------------------------------------------------------

  static const _fallbackChips = ['Coffee', 'Oatmeal', 'Water'];

  List<String> _buildChipLabels(List<MealLog> meals) {
    final seen = <String>{};
    final result = <String>[];
    for (final meal in meals) {
      if (result.length >= 5) break;
      final desc = meal.description;
      if (seen.add(desc)) {
        result.add(desc);
      }
    }
    // Pad with fallbacks (skip duplicates).
    for (final fallback in _fallbackChips) {
      if (result.length >= 5) break;
      if (seen.add(fallback)) {
        result.add(fallback);
      }
    }
    return result;
  }
}

// ---------------------------------------------------------------------------
// Voice button widget
// ---------------------------------------------------------------------------

class _VoiceButton extends StatelessWidget {
  final bool isListening;

  const _VoiceButton({required this.isListening});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isListening ? primary.withValues(alpha: 0.85) : primary,
        border: isListening
            ? Border.all(
                color: primary.withValues(alpha: 0.4),
                width: 6,
              )
            : null,
      ),
      child: const Icon(Icons.mic, color: Colors.white, size: 56),
    );
  }
}

// ---------------------------------------------------------------------------
// Review card widget
// ---------------------------------------------------------------------------

class _ReviewCard extends StatelessWidget {
  final MealLog meal;
  final VoidCallback onLog;
  final VoidCallback onEdit;

  const _ReviewCard({
    required this.meal,
    required this.onLog,
    required this.onEdit,
  });

  static String _inferMealType() {
    final hour = DateTime.now().hour;
    if (hour < 10) return 'Breakfast';
    if (hour < 14) return 'Lunch';
    if (hour < 18) return 'Snack';
    return 'Dinner';
  }

  @override
  Widget build(BuildContext context) {
    final suggestedType = _inferMealType();
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              meal.description,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              suggestedType,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onLog,
              child: const Text('Log it'),
            ),
            TextButton(
              onPressed: onEdit,
              child: const Text('Edit'),
            ),
          ],
        ),
      ),
    );
  }
}
