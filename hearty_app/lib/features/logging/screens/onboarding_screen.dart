import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/router.dart';
import '../../../core/auth/onboarding_provider.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();

  // Screen 1: Health profile state
  final Set<String> _selectedAllergens = {};
  final TextEditingController _conditionsController = TextEditingController();
  final Set<String> _selectedProtocols = {};

  // Screen 2: Notifications state
  bool _postMealEnabled = true;
  double _postMealDelay = 60.0; // minutes
  bool _morningCheckInEnabled = true;

  static const List<String> _allergens = [
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
    'Vegan',
    'Keto',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _conditionsController.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _finish() {
    // TODO Phase 5: save health profile to API
    ref.read(hasCompletedOnboardingProvider.notifier).state = true;
    context.goNamed(Routes.home);
  }

  void _skipToHome() {
    ref.read(hasCompletedOnboardingProvider.notifier).state = true;
    context.goNamed(Routes.home);
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
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 32),
          Text('Known allergens', style: textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _allergens.map((allergen) {
              return FilterChip(
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
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          Text('Known conditions', style: textTheme.labelLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _conditionsController,
            decoration: const InputDecoration(
              hintText: 'e.g., IBS, Acid Reflux',
              border: OutlineInputBorder(),
            ),
          ),
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
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: _skipToHome,
                child: const Text('Skip for now'),
              ),
              ElevatedButton(
                onPressed: () => _goToPage(1),
                child: const Text('Next →'),
              ),
            ],
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
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: _skipToHome,
                child: const Text('Skip for now'),
              ),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () => _goToPage(0),
                    child: const Text('← Back'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _goToPage(2),
                    child: const Text('Next →'),
                  ),
                ],
              ),
            ],
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: _skipToHome,
                child: const Text('Skip for now'),
              ),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () => _goToPage(1),
                    child: const Text('← Back'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _finish,
                    child: const Text('Finish'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
