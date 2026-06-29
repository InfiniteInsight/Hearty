import 'package:flutter/material.dart';

/// Aurora palette from the Hearty UI Design Guide (2026-05-28).
/// Deep navy background with emerald + violet accents. Token names mirror the
/// design-guide table so the spec maps 1:1 onto the code.
class Aurora {
  Aurora._();

  // Background — a 160° gradient from #0F1F2E to #112240.
  static const Color bgTop = Color(0xFF0F1F2E);
  static const Color bgBottom = Color(0xFF112240);
  static const LinearGradient background = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [bgTop, bgBottom],
  );

  // Accents
  static const Color accentGreen = Color(0xFF34D399); // "y" in logo, minute hand, meal dots
  static const Color accentViolet = Color(0xFF8B5CF6); // mood
  static const Color accentVioletLight = Color(0xFFA78BFA);
  static const Color accentRed = Color(0xFFF87171); // symptom

  // Text
  static const Color textPrimary = Color(0xFFFFFFFF); // headlines, "Heart" in logo
  static const Color textMuted = Color(0x4DFFFFFF); // 0.3 — timestamps, dates

  // Clock-specific
  static const Color clockNumMinor = Color(0x33FFFFFF); // 0.2 — minor clock numbers
  static const Color clockNumMajor = Color(0x8034D399); // emerald 0.5 — 12/3/6/9
  static const Color tickMinor = Color(0x1F34D399); // emerald 0.12
  static const Color tickMajor = Color(0x4D34D399); // emerald ~0.3 (major ticks)

  // Rings (from arc-labels companion spec)
  static const Color ringOuter = Color(0x3834D399); // 0.22 emerald — PM/outer
  static const Color ringMid = Color(0x1234D399); // 0.07 emerald — reference
  static const Color ringInner = Color(0x598B5CF6); // 0.35 violet — AM/inner
  static const Color ringInnerFill = Color(0x1A8B5CF6); // 0.1 violet

  // Orbit entry dots (arc-labels companion spec §2). AM dots sit in the violet
  // inner zone; PM dots in the emerald outer zone. Fill = soft tint, border = stronger.
  static const Color amMealFill = Color(0x338B5CF6); // violet 0.20
  static const Color amMealBorder = Color(0xE68B5CF6); // violet 0.90
  static const Color amSymptomFill = Color(0x33F87171); // red 0.20
  static const Color amSymptomBorder = Color(0xE6F87171); // red 0.90

  // Higher-contrast bubbles than the original spec tints — on the dark,
  // emerald-accented clock face the 8%/30% tints were nearly invisible (esp.
  // emerald meals blending into the emerald rings/numbers). Solid-ish borders +
  // a stronger fill read clearly as entry "bubbles".
  static const Color pmMealFill = Color(0x3334D399); // emerald 0.20
  static const Color pmMealBorder = Color(0xF234D399); // emerald 0.95
  static const Color pmSymptomFill = Color(0x33F87171); // red 0.20
  static const Color pmSymptomBorder = Color(0xE6F87171); // red 0.90
  static const Color pmMoodFill = Color(0x33A78BFA); // violet 0.20
  static const Color pmMoodBorder = Color(0xE6A78BFA); // violet 0.90
}
