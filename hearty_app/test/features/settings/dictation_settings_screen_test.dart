import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hearty_app/core/api/models/user_preferences.dart';
import 'package:hearty_app/core/api/providers/preferences_provider.dart';
import 'package:hearty_app/core/stt/asr_model_manager.dart';
import 'package:hearty_app/core/stt/on_device_model.dart';
import 'package:hearty_app/features/settings/screens/dictation_settings_screen.dart';
import 'package:hearty_app/features/voice/providers/voice_provider.dart';

class _FakePrefsNotifier extends PreferencesNotifier {
  _FakePrefsNotifier(this._seed);
  final UserPreferences _seed;

  @override
  Future<UserPreferences> build() async => _seed;

  @override
  Future<void> save(UserPreferences prefs) async {
    state = AsyncData(prefs);
  }
}

/// Stub manager: never touches the network or spawns an isolate. [fail] models
/// a download/warm failure so we can assert the pref does NOT flip.
class _FakeManager extends AsrModelManager {
  _FakeManager({this.fail = false}) : super(externalDir: () async => null);
  final bool fail;
  int calls = 0;

  @override
  Future<void> ensureAndWarm(
    OnDeviceModel model, {
    void Function(double progress)? onProgress,
  }) async {
    calls++;
    if (fail) throw StateError('boom');
    onProgress?.call(1.0);
  }
}

void main() {
  Future<ProviderContainer> pumpScreen(
    WidgetTester tester,
    UserPreferences seed, {
    AsrModelManager? manager,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesProvider.overrideWith(() => _FakePrefsNotifier(seed)),
          asrModelManagerProvider
              .overrideWithValue(manager ?? _FakeManager()),
        ],
        child: const MaterialApp(home: DictationSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(DictationSettingsScreen)));
  }

  group('DictationSettingsScreen', () {
    testWidgets('is its own page titled Dictation', (tester) async {
      await pumpScreen(tester, const UserPreferences());
      expect(find.widgetWithText(AppBar, 'Dictation'), findsOneWidget);
    });

    testWidgets('reflects saved auto-submit and cloud prefs', (tester) async {
      await pumpScreen(
          tester,
          const UserPreferences(autoSubmit: false, useCloudWhenOnline: true));
      final switches =
          tester.widgetList<SwitchListTile>(find.byType(SwitchListTile));
      final autoSubmit = switches
          .firstWhere((s) => (s.title as Text).data!.contains('Auto-submit'));
      final cloud = switches
          .firstWhere((s) => (s.title as Text).data!.contains('cloud'));
      expect(autoSubmit.value, isFalse);
      expect(cloud.value, isTrue);
    });

    testWidgets('toggling auto-submit persists the flipped value',
        (tester) async {
      final c = await pumpScreen(
          tester, const UserPreferences(autoSubmit: true));
      await tester.tap(find.widgetWithText(SwitchListTile, 'Auto-submit after a pause'));
      await tester.pumpAndSettle();
      expect(c.read(preferencesProvider).valueOrNull!.autoSubmit, isFalse);
    });

    testWidgets('toggling cloud persists the flipped value', (tester) async {
      final c = await pumpScreen(
          tester, const UserPreferences(useCloudWhenOnline: false));
      await tester
          .tap(find.widgetWithText(SwitchListTile, 'Use cloud when online'));
      await tester.pumpAndSettle();
      expect(
          c.read(preferencesProvider).valueOrNull!.useCloudWhenOnline, isTrue);
    });

    testWidgets('silence slider is disabled when auto-submit is off',
        (tester) async {
      await pumpScreen(tester, const UserPreferences(autoSubmit: false));
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.onChanged, isNull);
    });

    testWidgets('moving the slider persists the new silence seconds',
        (tester) async {
      final c = await pumpScreen(tester,
          const UserPreferences(autoSubmit: true, autoSubmitSilenceSeconds: 2.5));
      await tester.tap(find.byType(Slider)); // taps center → ~3.5s
      await tester.pumpAndSettle();
      final saved =
          c.read(preferencesProvider).valueOrNull!.autoSubmitSilenceSeconds;
      expect(saved, isNot(2.5));
      expect(saved, inInclusiveRange(2.0, 5.0));
    });

    testWidgets('switching to a model that prepares OK flips the pref',
        (tester) async {
      final mgr = _FakeManager();
      final c = await pumpScreen(tester, const UserPreferences(), manager: mgr);
      // Default is parakeet; pick Moonshine.
      await tester.tap(find.text('Moonshine'));
      await tester.pumpAndSettle();
      expect(mgr.calls, 1);
      expect(c.read(preferencesProvider).valueOrNull!.useOnDeviceModel,
          'moonshine');
      expect(find.text('Moonshine ready'), findsOneWidget);
    });

    testWidgets('a failed model switch keeps the current model selected',
        (tester) async {
      final mgr = _FakeManager(fail: true);
      final c = await pumpScreen(tester, const UserPreferences(), manager: mgr);
      await tester.tap(find.text('Moonshine'));
      await tester.pumpAndSettle();
      expect(mgr.calls, 1);
      // Pref must NOT have flipped to a model that never downloaded.
      expect(c.read(preferencesProvider).valueOrNull!.useOnDeviceModel,
          'parakeet');
      expect(find.textContaining('keeping current model'), findsOneWidget);
    });
  });
}
