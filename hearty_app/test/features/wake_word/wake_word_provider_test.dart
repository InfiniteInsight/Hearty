import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/features/wake_word/providers/wake_word_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('wakeWordDetectedProvider', () {
    test('initial state is false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(wakeWordDetectedProvider), isFalse);
    });

    test('setDetected(true) sets state to true', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(wakeWordDetectedProvider.notifier).setDetected(true);
      expect(container.read(wakeWordDetectedProvider), isTrue);
    });

    test('setDetected(false) clears state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(wakeWordDetectedProvider.notifier).setDetected(true);
      container.read(wakeWordDetectedProvider.notifier).setDetected(false);
      expect(container.read(wakeWordDetectedProvider), isFalse);
    });
  });
}
