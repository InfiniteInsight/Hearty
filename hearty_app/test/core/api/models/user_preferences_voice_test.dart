import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/api/models/user_preferences.dart';

void main() {
  group('UserPreferences voice settings', () {
    test('defaults: cloud dormant, auto-submit on at 2.5s, moonshine model', () {
      const p = UserPreferences();
      expect(p.useCloudWhenOnline, isFalse);
      expect(p.autoSubmit, isTrue);
      expect(p.autoSubmitSilenceSeconds, 2.5);
      expect(p.useOnDeviceModel, 'moonshine');
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
      expect(back.useOnDeviceModel, 'moonshine');
    });
  });
}
