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
}
