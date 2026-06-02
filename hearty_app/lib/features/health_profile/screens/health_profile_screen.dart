import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

  Widget _header(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                    icon: const Icon(Icons.check),
                    onPressed: _save,
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header('Allergens'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AllergensSection(
                selected: _allergens,
                onChanged: (v) => setState(() => _allergens = v),
              ),
            ),
            _header('Dietary Protocols'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DietaryProtocolsSection(
                selected: _protocols,
                onChanged: (v) => setState(() => _protocols = v),
              ),
            ),
            _header('Conditions'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ConditionsSection(
                selected: _conditions,
                onChanged: (v) => setState(() => _conditions = v),
              ),
            ),
            _header('Medications & Supplements'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: MedicationsSection(
                medications: _medications,
                onChanged: (v) => setState(() => _medications = v),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
