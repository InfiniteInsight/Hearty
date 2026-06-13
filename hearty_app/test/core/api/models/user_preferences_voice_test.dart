import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/api/models/user_preferences.dart';

void main() {
  group('UserPreferences voice settings', () {
    test('defaults: cloud dormant, auto-submit on at 2.5s, parakeet-110m model',
        () {
      const p = UserPreferences();
      expect(p.useCloudWhenOnline, isFalse);
      expect(p.autoSubmit, isTrue);
      expect(p.autoSubmitSilenceSeconds, 2.5);
      expect(p.useOnDeviceModel, 'parakeetCtc110m');
    });

    test('round-trips through json', () {
      const p = UserPreferences(
        useCloudWhenOnline: true,
        autoSubmit: false,
        autoSubmitSilenceSeconds: 4.0,
        useOnDeviceModel: 'parakeet',
      );
      final back = UserPreferences.fromJson(p.toJson());
      expect(back.useCloudWhenOnline, isTrue);
      expect(back.autoSubmit, isFalse);
      expect(back.autoSubmitSilenceSeconds, 4.0);
      expect(back.useOnDeviceModel, 'parakeet');
    });

    test('absent json keys fall back to defaults', () {
      final back = UserPreferences.fromJson({});
      expect(back.useCloudWhenOnline, isFalse);
      expect(back.autoSubmit, isTrue);
      expect(back.autoSubmitSilenceSeconds, 2.5);
      expect(back.useOnDeviceModel, 'parakeetCtc110m');
    });
  });

  group('UserPreferences trendsConversationEnabled', () {
    test('defaults to true', () {
      const p = UserPreferences();
      expect(p.trendsConversationEnabled, isTrue);
    });

    test('round-trips through json', () {
      const p = UserPreferences(trendsConversationEnabled: false);
      final back = UserPreferences.fromJson(p.toJson());
      expect(back.trendsConversationEnabled, isFalse);
    });

    test('absent json key falls back to true', () {
      final back = UserPreferences.fromJson({});
      expect(back.trendsConversationEnabled, isTrue);
    });

    test('copyWith overrides the field', () {
      const p = UserPreferences();
      expect(p.copyWith(trendsConversationEnabled: false).trendsConversationEnabled,
          isFalse);
    });
  });
}
