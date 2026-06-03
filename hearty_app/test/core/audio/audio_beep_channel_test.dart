import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/audio/audio_beep_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.hearty.app/audio');
  final calls = <MethodCall>[];

  void mock(Future<dynamic> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  setUp(() {
    calls.clear();
    mock((call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() => mock((_) async => null));

  test('suppress invokes setBeepSuppressed(true)', () async {
    await AudioBeepChannel().suppress();
    expect(calls.single.method, 'setBeepSuppressed');
    expect(calls.single.arguments, true);
  });

  test('restore invokes setBeepSuppressed(false)', () async {
    await AudioBeepChannel().restore();
    expect(calls.single.method, 'setBeepSuppressed');
    expect(calls.single.arguments, false);
  });

  test('platform exceptions are swallowed (no throw)', () async {
    mock((_) async => throw PlatformException(code: 'boom'));
    await AudioBeepChannel().suppress(); // must not throw
    await AudioBeepChannel().restore(); // must not throw
  });
}
