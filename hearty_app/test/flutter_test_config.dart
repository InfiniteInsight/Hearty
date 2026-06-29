import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the bundled design fonts before any test runs so golden files render
/// real glyphs (without this, `flutter test` draws text as filled boxes).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _load('Fraunces', 'assets/fonts/Fraunces.ttf');
  await _load('Plus Jakarta Sans', 'assets/fonts/PlusJakartaSans.ttf');
  await _load('JetBrains Mono', 'assets/fonts/JetBrainsMono.ttf');
  await testMain();
}

Future<void> _load(String family, String asset) async {
  final loader = FontLoader(family)..addFont(rootBundle.load(asset));
  await loader.load();
}
