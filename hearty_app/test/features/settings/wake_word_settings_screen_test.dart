import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hearty_app/core/api/models/user_preferences.dart';
import 'package:hearty_app/core/api/providers/preferences_provider.dart';
import 'package:hearty_app/features/settings/screens/wake_word_settings_screen.dart';

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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Stub the wake-word control channel so start/stopService no-op in tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.hearty.app/wake_word_control'),
      (call) async => null,
    );
  });

  Future<void> pumpScreen(WidgetTester tester, UserPreferences seed) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesProvider.overrideWith(() => _FakePrefsNotifier(seed)),
        ],
        child: const MaterialApp(home: WakeWordSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('WakeWordSettingsScreen', () {
    testWidgets('is its own page titled Wake Word', (tester) async {
      await pumpScreen(tester, const UserPreferences(wakeWordEnabled: true));
      expect(find.widgetWithText(AppBar, 'Wake Word'), findsOneWidget);
    });

    testWidgets('reflects the saved wake-word preference', (tester) async {
      await pumpScreen(tester, const UserPreferences(wakeWordEnabled: false));
      final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(tile.value, isFalse);
    });

    testWidgets('toggling persists the flipped value', (tester) async {
      await pumpScreen(tester, const UserPreferences(wakeWordEnabled: true));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(tile.value, isFalse,
          reason: 'toggle should save and reflect the new pref');
    });
  });
}
