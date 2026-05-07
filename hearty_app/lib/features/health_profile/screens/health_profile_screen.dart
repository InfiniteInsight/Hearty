import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/providers/preferences_provider.dart';

class HealthProfileScreen extends ConsumerStatefulWidget {
  const HealthProfileScreen({super.key});

  @override
  ConsumerState<HealthProfileScreen> createState() =>
      _HealthProfileScreenState();
}

class _HealthProfileScreenState extends ConsumerState<HealthProfileScreen> {
  static const _bigNineAllergens = [
    'Gluten',
    'Dairy',
    'Eggs',
    'Tree Nuts',
    'Peanuts',
    'Soy',
    'Shellfish',
    'Fish',
    'Sesame',
  ];

  static const _fixedProtocols = [
    'Gluten-Free',
    'Dairy-Free',
    'Low-FODMAP',
    'Vegetarian',
    'Vegan',
    'Keto',
  ];

  List<String> _allergens = [];
  List<String> _conditions = [];
  List<String> _protocols = [];
  List<String> _medications = [];
  bool _isSaving = false;

  final _conditionController = TextEditingController();
  final _medicationController = TextEditingController();

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

  @override
  void dispose() {
    _conditionController.dispose();
    _medicationController.dispose();
    super.dispose();
  }

  Future<void> _savePreferences() async {
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

  Future<void> _showAddDialog({
    required String title,
    required void Function(String) onConfirm,
  }) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (_) {
            final text = controller.text.trim();
            if (text.isNotEmpty) {
              onConfirm(text);
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
                onConfirm(text);
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

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildAllergensSection() {
    final customAllergens =
        _allergens.where((a) => !_bigNineAllergens.contains(a)).toList();
    final allChipAllergens = [..._bigNineAllergens, ...customAllergens];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Allergens'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ...allChipAllergens.map(
                (allergen) => FilterChip(
                  label: Text(allergen),
                  selected: _allergens.contains(allergen),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        if (!_allergens.contains(allergen)) {
                          _allergens = [..._allergens, allergen];
                        }
                      } else {
                        _allergens =
                            _allergens.where((a) => a != allergen).toList();
                      }
                    });
                  },
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.add),
                label: const Text('Add'),
                onPressed: () => _showAddDialog(
                  title: 'Add Allergen',
                  onConfirm: (text) {
                    if (!_allergens.contains(text)) {
                      setState(() => _allergens = [..._allergens, text]);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConditionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Conditions'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _conditionController,
            decoration: InputDecoration(
              hintText: 'Add a condition (e.g. IBS)',
              suffixIcon: IconButton(
                icon: const Icon(Icons.send),
                onPressed: () {
                  final text = _conditionController.text.trim();
                  if (text.isNotEmpty) {
                    setState(() {
                      _conditions = [..._conditions, text];
                      _conditionController.clear();
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
                  _conditionController.clear();
                });
              }
            },
          ),
        ),
        if (_conditions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _conditions
                  .map(
                    (condition) => InputChip(
                      label: Text(condition),
                      onDeleted: () {
                        setState(() {
                          _conditions = _conditions
                              .where((c) => c != condition)
                              .toList();
                        });
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildProtocolsSection() {
    final customProtocols =
        _protocols.where((p) => !_fixedProtocols.contains(p)).toList();
    final allChipProtocols = [..._fixedProtocols, ...customProtocols];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Dietary Protocols'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ...allChipProtocols.map(
                (protocol) => FilterChip(
                  label: Text(protocol),
                  selected: _protocols.contains(protocol),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        if (!_protocols.contains(protocol)) {
                          _protocols = [..._protocols, protocol];
                        }
                      } else {
                        _protocols =
                            _protocols.where((p) => p != protocol).toList();
                      }
                    });
                  },
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.add),
                label: const Text('Add'),
                onPressed: () => _showAddDialog(
                  title: 'Add Dietary Protocol',
                  onConfirm: (text) {
                    if (!_protocols.contains(text)) {
                      setState(() => _protocols = [..._protocols, text]);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMedicationsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Medications & Supplements'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _medicationController,
            decoration: InputDecoration(
              hintText: 'Add medication or supplement',
              suffixIcon: IconButton(
                icon: const Icon(Icons.send),
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
        ),
        if (_medications.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _medications
                  .map(
                    (med) => InputChip(
                      label: Text(med),
                      onDeleted: () {
                        setState(() {
                          _medications =
                              _medications.where((m) => m != med).toList();
                        });
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }

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
                    onPressed: _savePreferences,
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAllergensSection(),
            _buildConditionsSection(),
            _buildProtocolsSection(),
            _buildMedicationsSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
