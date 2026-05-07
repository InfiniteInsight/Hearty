import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/models/meal_log.dart';
import '../../../core/api/offline_exception.dart';
import '../../../core/api/providers/meals_provider.dart';
import '../../voice/models/voice_state.dart';
import '../../voice/providers/voice_provider.dart';
import '../../voice/screens/voice_overlay_screen.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _inferMealType() {
  final hour = DateTime.now().hour;
  if (hour < 10) return 'Breakfast';
  if (hour < 14) return 'Lunch';
  if (hour < 18) return 'Snack';
  return 'Dinner';
}

/// Formats [dt] as "H:MM AM/PM" (no leading zero on hour).
String _formatFollowUpTime(DateTime dt) {
  final hour = dt.hour;
  final minute = dt.minute;
  final period = hour < 12 ? 'AM' : 'PM';
  final displayHour = hour % 12 == 0 ? 12 : hour % 12;
  final minuteStr = minute.toString().padLeft(2, '0');
  return "I'll check in at $displayHour:$minuteStr $period";
}

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

  /// Non-null when the review card is showing; holds the text the user submitted.
  String? _reviewText;

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

  /// Shows the review card immediately — no API call yet.
  void _submitText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _reviewText = trimmed;
    });
  }

  /// Called by _ReviewCard's "Log it" button. Saves via provider.
  Future<void> _logMeal(String description) async {
    await ref.read(mealsProvider.notifier).logMeal(description);

    if (!mounted) return;

    final mealsState = ref.read(mealsProvider);
    if (mealsState.hasError) {
      final err = mealsState.error;
      final msg = err is OfflineException
          ? err.message
          : 'Failed to log meal — please try again';
      _showError(msg);
      // Re-throw so _ReviewCard knows to clear _saving.
      throw Exception(msg);
    }

    // Success: clear the text field and pop.
    _textController.clear();
    if (mounted) context.pop();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _onEditPressed() {
    setState(() {
      _textController.text = _reviewText ?? '';
      _reviewText = null;
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final voiceState = ref.watch(voiceProvider);
    final isListening = voiceState.status == VoiceStatus.listening ||
        voiceState.status == VoiceStatus.awaitingFollowUp;

    final mealsAsync = ref.watch(mealsProvider);
    final recentChipLabels = _buildChipLabels(mealsAsync.valueOrNull ?? []);

    final reviewText = _reviewText;

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

            // ── Review card (appears before saving) ───────────────────────
            if (reviewText != null)
              _ReviewCard(
                initialDescription: reviewText,
                mealType: _inferMealType(),
                followUpTime: _formatFollowUpTime(
                  DateTime.now().add(const Duration(minutes: 45)),
                ),
                onLog: _logMeal,
                onEdit: _onEditPressed,
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

class _ReviewCard extends StatefulWidget {
  final String initialDescription;
  final String mealType;
  final String followUpTime;
  final Future<void> Function(String description) onLog;
  final VoidCallback onEdit;

  const _ReviewCard({
    required this.initialDescription,
    required this.mealType,
    required this.followUpTime,
    required this.onLog,
    required this.onEdit,
  });

  @override
  State<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<_ReviewCard> {
  late final TextEditingController _descController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _descController = TextEditingController(text: widget.initialDescription);
  }

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  Future<void> _handleLog() async {
    setState(() => _saving = true);
    try {
      await widget.onLog(_descController.text.trim());
    } catch (_) {
      // Error already shown via snackbar in the parent; reset button.
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Editable description
            TextFormField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: 'What you had',
                border: OutlineInputBorder(),
              ),
              maxLines: null,
            ),

            const SizedBox(height: 12),

            // Inferred meal type label
            Text(
              widget.mealType,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),

            const SizedBox(height: 8),

            // Suggested follow-up time
            Row(
              children: [
                Icon(
                  Icons.notifications_none,
                  size: 18,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.followUpTime,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Log it button (shows spinner while saving)
            ElevatedButton(
              onPressed: _saving ? null : _handleLog,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Log it'),
            ),

            TextButton(
              onPressed: _saving ? null : widget.onEdit,
              child: const Text('Edit'),
            ),
          ],
        ),
      ),
    );
  }
}
