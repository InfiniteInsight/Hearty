import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../app/theme/aurora_colors.dart';
import '../../../core/api/providers/preferences_provider.dart';
import '../../../core/widgets/health_profile/allergens_section.dart';
import '../../../core/widgets/health_profile/conditions_section.dart';
import '../../../core/widgets/health_profile/dietary_protocols_section.dart';
import '../../../core/widgets/health_profile/medications_section.dart';

class HealthProfileScreen extends ConsumerStatefulWidget {
  const HealthProfileScreen({super.key});

  @override
  ConsumerState<HealthProfileScreen> createState() =>
      _HealthProfileScreenState();
}

class _HealthProfileScreenState extends ConsumerState<HealthProfileScreen> {
  List<String> _allergens = [];
  List<String> _conditions = [];
  List<String> _protocols = [];
  List<String> _medications = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prefs = ref.read(preferencesProvider).valueOrNull;
      if (prefs != null && mounted) {
        setState(() {
          _allergens = List.from(prefs.allergens);
          _conditions = List.from(prefs.conditions);
          _protocols = List.from(prefs.dietaryProtocols);
          _medications = List.from(prefs.medications);
        });
      }
    });
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final prefs = ref.read(preferencesProvider).valueOrNull;
    if (prefs == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save — please try again')),
        );
        setState(() => _isSaving = false);
      }
      return;
    }
    await ref.read(preferencesProvider.notifier).save(
          prefs.copyWith(
            allergens: _allergens,
            conditions: _conditions,
            dietaryProtocols: _protocols,
            medications: _medications,
          ),
        );
    if (!mounted) return;
    final saved = ref.read(preferencesProvider);
    if (saved.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save — please try again')),
      );
      setState(() => _isSaving = false);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Health profile saved')),
      );
      context.pop();
    }
  }

  Widget _header(String title) => Text(
        title,
        style: const TextStyle(
          color: Aurora.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      );

  /// An Aurora glass card wrapping one category: a white section header on top
  /// and the section's chips/field below.
  Widget _card(String title, Widget child) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Aurora.glassFill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Aurora.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(title),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.aurora,
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: Aurora.background),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('Health Profile'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _isSaving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: const Icon(Icons.check, color: Aurora.accentGreen),
                        onPressed: _save,
                      ),
              ),
            ],
          ),
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                _card(
                  'Allergens',
                  AllergensSection(
                    aurora: true,
                    selected: _allergens,
                    onChanged: (v) => setState(() => _allergens = v),
                  ),
                ),
                _card(
                  'Dietary Protocols',
                  DietaryProtocolsSection(
                    aurora: true,
                    selected: _protocols,
                    onChanged: (v) => setState(() => _protocols = v),
                  ),
                ),
                _card(
                  'Conditions',
                  ConditionsSection(
                    aurora: true,
                    selected: _conditions,
                    onChanged: (v) => setState(() => _conditions = v),
                  ),
                ),
                _card(
                  'Medications & Supplements',
                  MedicationsSection(
                    aurora: true,
                    medications: _medications,
                    onChanged: (v) => setState(() => _medications = v),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
