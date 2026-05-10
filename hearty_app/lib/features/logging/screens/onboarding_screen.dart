import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/router.dart';
import '../../../core/api/providers/preferences_provider.dart';
import '../../../core/api/models/user_preferences.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();

  // Screen 1: Health profile state
  final Set<String> _selectedAllergens = {};
  List<String> _customAllergens = [];
  final TextEditingController _conditionsController = TextEditingController();
  List<String> _conditions = [];
  final Set<String> _selectedProtocols = {};
  final TextEditingController _medicationController = TextEditingController();
  List<String> _medications = [];

  // Screen 2: Notifications state
  bool _postMealEnabled = true;
  double _postMealDelay = 60.0; // minutes
  bool _morningCheckInEnabled = true;

  static const List<String> _builtInAllergens = [
    'Gluten',
    'Dairy',
    'Eggs',
    'Nuts',
    'Soy',
    'Shellfish',
    'Fish',
    'Sesame',
  ];

  static const List<String> _protocols = [
    'Gluten-Free',
    'Dairy-Free',
    'Low-FODMAP',
    'Vegetarian',
    'Pescetarian',
    'Vegan',
    'Keto',
    'Paleo',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _conditionsController.dispose();
    _medicationController.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _markOnboardingComplete() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        await Supabase.instance.client
            .from('user_profiles')
            .upsert({'id': user.id}, onConflict: 'id');
      } catch (_) {
        // Non-fatal: router will re-check on next auth event.
      }
    }
  }

  Future<void> _finish() async {
    await _markOnboardingComplete();

    try {
      final existing =
          ref.read(preferencesProvider).valueOrNull ?? const UserPreferences();
      await ref.read(preferencesProvider.notifier).save(
            existing.copyWith(
              allergens: [
                ..._selectedAllergens,
                ..._customAllergens,
              ],
              conditions: _conditions,
              dietaryProtocols: _selectedProtocols.toList(),
              medications: _medications,
              postMealNudgeEnabled: _postMealEnabled,
              nudgeDelayMinutes: _postMealDelay.round(),
              dailyCheckinEnabled: _morningCheckInEnabled,
            ),
          );
    } catch (_) {
      // Non-fatal: user can update profile in Settings.
    }

    if (mounted) context.goNamed(Routes.home);
  }

  Future<void> _skipToHome() async {
    await _markOnboardingComplete();
    if (mounted) context.goNamed(Routes.home);
  }

  Future<void> _showAddAllergenDialog() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Allergen'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (_) {
            final text = controller.text.trim();
            if (text.isNotEmpty) {
              setState(() {
                if (!_customAllergens.contains(text)) {
                  _customAllergens = [..._customAllergens, text];
                }
                _selectedAllergens.add(text);
              });
              Navigator.of(ctx).pop();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                setState(() {
                  if (!_customAllergens.contains(text)) {
                    _customAllergens = [..._customAllergens, text];
                  }
                  _selectedAllergens.add(text);
                });
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Widget _buildNavRow({
    required bool showBack,
    required VoidCallback? onBack,
    required VoidCallback? onForward,
    required String forwardLabel,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: TextButton(
            onPressed: _skipToHome,
            child: const Text('Skip'),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showBack) ...[
              OutlinedButton(
                onPressed: onBack,
                child: const Text('Back'),
              ),
              const SizedBox(width: 8),
            ],
            ElevatedButton(
              onPressed: onForward,
              child: Text(forwardLabel),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildPage1(context),
            _buildPage2(context),
            _buildPage3(context),
          ],
        ),
      ),
    );
  }

  Widget _buildPage1(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final allAllergens = [..._builtInAllergens, ..._customAllergens];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text('Tell us about your health',
              style: textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            "We'll use this to personalize your experience.",
            style: textTheme.bodyMedium?.copyWith(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 32),
          Text('Known allergens', style: textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ...allAllergens.map((allergen) => FilterChip(
                    label: Text(allergen),
                    selected: _selectedAllergens.contains(allergen),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedAllergens.add(allergen);
                        } else {
                          _selectedAllergens.remove(allergen);
                        }
                      });
                    },
                  )),
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: const Text('Add'),
                onPressed: _showAddAllergenDialog,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Known conditions', style: textTheme.labelLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _conditionsController,
            decoration: InputDecoration(
              hintText: 'Add a condition (e.g. IBS)',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.add),
                onPressed: () {
                  final text = _conditionsController.text.trim();
                  if (text.isNotEmpty) {
                    setState(() {
                      _conditions = [..._conditions, text];
                      _conditionsController.clear();
                    });
                  }
                },
              ),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (text) {
              text = text.trim();
              if (text.isNotEmpty) {
                setState(() {
                  _conditions = [..._conditions, text];
                  _conditionsController.clear();
                });
              }
            },
          ),
          if (_conditions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _conditions
                  .map((c) => InputChip(
                        label: Text(c),
                        onDeleted: () => setState(
                            () => _conditions =
                                _conditions.where((x) => x != c).toList()),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 24),
          Text('Dietary protocols', style: textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _protocols.map((protocol) {
              return FilterChip(
                label: Text(protocol),
                selected: _selectedProtocols.contains(protocol),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedProtocols.add(protocol);
                    } else {
                      _selectedProtocols.remove(protocol);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          Text('Medications & supplements', style: textTheme.labelLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _medicationController,
            decoration: InputDecoration(
              hintText: 'Add medication or supplement',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.add),
                onPressed: () {
                  final text = _medicationController.text.trim();
                  if (text.isNotEmpty) {
                    setState(() {
                      _medications = [..._medications, text];
                      _medicationController.clear();
                    });
                  }
                },
              ),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (text) {
              text = text.trim();
              if (text.isNotEmpty) {
                setState(() {
                  _medications = [..._medications, text];
                  _medicationController.clear();
                });
              }
            },
          ),
          if (_medications.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _medications
                  .map((m) => InputChip(
                        label: Text(m),
                        onDeleted: () => setState(
                            () => _medications =
                                _medications.where((x) => x != m).toList()),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 32),
          _buildNavRow(
            showBack: false,
            onBack: null,
            onForward: () => _goToPage(1),
            forwardLabel: 'Next →',
          ),
        ],
      ),
    );
  }

  Widget _buildPage2(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text('Set up notifications',
              style: textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            "We'll remind you to log how you're feeling.",
            style: textTheme.bodyMedium?.copyWith(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 32),
          SwitchListTile(
            title: const Text('Post-meal check-in'),
            value: _postMealEnabled,
            onChanged: (value) => setState(() => _postMealEnabled = value),
            contentPadding: EdgeInsets.zero,
          ),
          if (_postMealEnabled) ...[
            const SizedBox(height: 8),
            Text(
              'Delay: ${_postMealDelay.round()} min',
              style: textTheme.bodyMedium,
            ),
            Slider(
              value: _postMealDelay,
              min: 30,
              max: 90,
              divisions: 12,
              label: '${_postMealDelay.round()} min',
              onChanged: (value) => setState(() => _postMealDelay = value),
            ),
          ],
          SwitchListTile(
            title: const Text('Daily morning check-in'),
            value: _morningCheckInEnabled,
            onChanged: (value) =>
                setState(() => _morningCheckInEnabled = value),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 32),
          _buildNavRow(
            showBack: true,
            onBack: () => _goToPage(0),
            onForward: () => _goToPage(2),
            forwardLabel: 'Next →',
          ),
        ],
      ),
    );
  }

  Widget _buildPage3(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text('Background wake word',
              style: textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            "Hearty can listen for 'Hey Hearty' in the background (~1-2% battery/hour). "
            'For best results, exempt Hearty from battery optimization.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () async {
              await Permission.ignoreBatteryOptimizations.request();
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
            child: const Text('Exempt from battery optimization'),
          ),
          const SizedBox(height: 32),
          _buildNavRow(
            showBack: true,
            onBack: () => _goToPage(1),
            onForward: _finish,
            forwardLabel: 'Finish',
          ),
        ],
      ),
    );
  }
}
