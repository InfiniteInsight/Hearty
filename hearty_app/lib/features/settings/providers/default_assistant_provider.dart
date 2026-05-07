import 'package:flutter_riverpod/flutter_riverpod.dart';

enum DefaultAssistant { googleAssistant, gemini, none }

extension DefaultAssistantLabel on DefaultAssistant {
  String get label {
    switch (this) {
      case DefaultAssistant.googleAssistant: return 'Google Assistant';
      case DefaultAssistant.gemini: return 'Gemini';
      case DefaultAssistant.none: return 'None';
    }
  }
}

final defaultAssistantProvider =
    StateProvider<DefaultAssistant>((ref) => DefaultAssistant.googleAssistant);
