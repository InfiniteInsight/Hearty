import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../app/theme/aurora_colors.dart';

/// Type of an entry orbiting the clock — drives the dot's color.
enum ClockEntryType { meal, symptom, mood }

/// One entry placed around the dial by its time of day.
class ClockEntry {
  final DateTime time;
  final ClockEntryType type;

  const ClockEntry({required this.time, required this.type});

  /// Clock angle in degrees (0° = 12 o'clock, clockwise).
  double get angleDeg => (time.hour % 12 + time.minute / 60) * 30;

  /// AM entries orbit the inner ring; PM entries the outer ring.
  bool get isAm => time.hour < 12;
}

/// Radial-clock face (Hearty UI Design Guide §"Radial Clock — Geometry", Aurora
/// palette). Phases 1–2: rings, tick marks, clock numbers, hour/minute hands, a
/// center digital-time readout, and orbit entry dots placed by time (AM inner /
/// PM outer). Tap interaction and arc labels come in later phases.
///
/// Geometry uses the design guide's logical-pixel radii on a square canvas of
/// side [designSize] (278). Everything scales to whatever box it is given, so it
/// stays centered and uncropped on narrow phones.
class RadialClock extends StatelessWidget {
  /// The time to display. Defaults to [DateTime.now] when null (tests pass a
  /// fixed value for deterministic goldens).
  final DateTime? time;

  /// Entries to orbit the dial (today's meals/symptoms).
  final List<ClockEntry> entries;

  /// Side length of the (square) clock zone in logical pixels.
  final double size;

  const RadialClock({
    super.key,
    this.time,
    this.entries = const [],
    this.size = 278,
  });

  static const double designSize = 278;
  static const double _rAmOrbit = 60;
  static const double _rPmOrbit = 118;

  @override
  Widget build(BuildContext context) {
    final DateTime t = time ?? DateTime.now();
    final double s = size / designSize;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _RadialClockPainter(time: t)),
          ),
          for (final e in entries) _positionDot(e, s),
        ],
      ),
    );
  }

  Widget _positionDot(ClockEntry e, double s) {
    final double r = (e.isAm ? _rAmOrbit : _rPmOrbit) * s;
    final double dotSize = (e.isAm ? 26.0 : 34.0) * s;
    final double rad = e.angleDeg * math.pi / 180;
    final double cx = size / 2 + r * math.sin(rad);
    final double cy = size / 2 - r * math.cos(rad);
    return Positioned(
      left: cx - dotSize / 2,
      top: cy - dotSize / 2,
      child: _OrbitDot(type: e.type, isAm: e.isAm, size: dotSize),
    );
  }
}

/// A single orbit marker — a bordered, softly-filled circle colored by entry
/// type and AM/PM zone.
class _OrbitDot extends StatelessWidget {
  final ClockEntryType type;
  final bool isAm;
  final double size;

  const _OrbitDot({required this.type, required this.isAm, required this.size});

  @override
  Widget build(BuildContext context) {
    final (Color fill, Color border) = switch ((type, isAm)) {
      (ClockEntryType.meal, true) => (Aurora.amMealFill, Aurora.amMealBorder),
      (ClockEntryType.symptom, true) => (
        Aurora.amSymptomFill,
        Aurora.amSymptomBorder,
      ),
      (ClockEntryType.mood, true) => (Aurora.amMealFill, Aurora.amMealBorder),
      (ClockEntryType.meal, false) => (Aurora.pmMealFill, Aurora.pmMealBorder),
      (ClockEntryType.symptom, false) => (
        Aurora.pmSymptomFill,
        Aurora.pmSymptomBorder,
      ),
      (ClockEntryType.mood, false) => (Aurora.pmMoodFill, Aurora.pmMoodBorder),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(color: border, width: isAm ? 1.5 : 1.5),
      ),
    );
  }
}

class _RadialClockPainter extends CustomPainter {
  final DateTime time;

  _RadialClockPainter({required this.time});

  // Design-guide radii (logical px on a 278 canvas).
  static const double _rInner = 45; // AM ring
  static const double _rMid = 80; // reference ring
  static const double _rOuter = 108; // PM ring
  static const double _rNumbers = 88;
  static const double _rTick = 103;
  static const double _hourHandLen = 38;
  static const double _minuteHandLen = 56;

  @override
  void paint(Canvas canvas, Size size) {
    // Uniform scale from the 278 design space to the actual box.
    final double s = math.min(size.width, size.height) / RadialClock.designSize;
    final Offset c = Offset(size.width / 2, size.height / 2);

    _drawRings(canvas, c, s);
    _drawTicks(canvas, c, s);
    _drawNumbers(canvas, c, s);
    _drawHands(canvas, c, s);
    _drawCenter(canvas, c, s);
  }

  /// Point on a circle of radius [r] at clock angle [deg] (0° = 12 o'clock,
  /// increasing clockwise).
  Offset _polar(Offset c, double r, double deg) {
    final double rad = deg * math.pi / 180;
    return Offset(c.dx + r * math.sin(rad), c.dy - r * math.cos(rad));
  }

  void _drawRings(Canvas canvas, Offset c, double s) {
    void ring(double r, Color color, double width, {Color? fill}) {
      if (fill != null) {
        canvas.drawCircle(c, r * s, Paint()..color = fill);
      }
      canvas.drawCircle(
        c,
        r * s,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * s
          ..color = color,
      );
    }

    ring(_rOuter, Aurora.ringOuter, 1.0);
    ring(_rMid, Aurora.ringMid, 1.0);
    ring(_rInner, Aurora.ringInner, 1.5, fill: Aurora.ringInnerFill);
  }

  void _drawTicks(Canvas canvas, Offset c, double s) {
    for (int i = 0; i < 12; i++) {
      final double deg = i * 30.0;
      final bool major = deg % 90 == 0;
      final double len = (major ? 10.0 : 7.0) * s;
      final Offset outer = _polar(c, _rTick * s, deg);
      // inner end of the tick, pointing toward center
      final double rad = deg * math.pi / 180;
      final Offset inner = Offset(
        outer.dx - len * math.sin(rad),
        outer.dy + len * math.cos(rad),
      );
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = (major ? 2.0 : 1.5) * s
          ..color = major ? Aurora.tickMajor : Aurora.tickMinor,
      );
    }
  }

  void _drawNumbers(Canvas canvas, Offset c, double s) {
    for (int hour = 1; hour <= 12; hour++) {
      final double deg = (hour % 12) * 30.0;
      final bool major = hour % 3 == 0; // 12, 3, 6, 9
      final tp = TextPainter(
        text: TextSpan(
          text: '$hour',
          style: TextStyle(
            fontFamily: 'Plus Jakarta Sans',
            fontSize: (major ? 15.0 : 13.0) * s,
            fontWeight: major ? FontWeight.w700 : FontWeight.w600,
            color: major ? Aurora.clockNumMajor : Aurora.clockNumMinor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final Offset p = _polar(c, _rNumbers * s, deg);
      tp.paint(canvas, Offset(p.dx - tp.width / 2, p.dy - tp.height / 2));
    }
  }

  void _drawHands(Canvas canvas, Offset c, double s) {
    final int minutes = time.minute;
    final double hourDeg = (time.hour % 12 + minutes / 60) * 30;
    final double minuteDeg = minutes * 6.0;

    void hand(double len, double width, double deg, Color color) {
      final Offset end = _polar(c, len * s, deg);
      canvas.drawLine(
        c,
        end,
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width * s
          ..color = color,
      );
    }

    hand(_hourHandLen, 3, hourDeg, Aurora.textPrimary);
    hand(_minuteHandLen, 2, minuteDeg, Aurora.accentGreen);
  }

  void _drawCenter(Canvas canvas, Offset c, double s) {
    // Compact center hub: a subtle disc masks the hand pivot, with the digital
    // readout on top and a small emerald pivot ring so the hands read as
    // radiating from an intentional center rather than poking out raggedly.
    final int h12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final String hhmm = '$h12:${time.minute.toString().padLeft(2, '0')}';
    final String ampm = time.hour < 12 ? 'AM' : 'PM';

    canvas.drawCircle(
      c,
      24 * s,
      Paint()..color = Aurora.bgBottom.withValues(alpha: 0.82),
    );
    // thin emerald hub ring
    canvas.drawCircle(
      c,
      24 * s,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 * s
        ..color = Aurora.accentGreen.withValues(alpha: 0.25),
    );

    final timeTp = TextPainter(
      text: TextSpan(
        text: hhmm,
        style: TextStyle(
          fontFamily: 'JetBrains Mono',
          fontSize: 16 * s,
          fontWeight: FontWeight.w700,
          color: Aurora.textPrimary,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final ampmTp = TextPainter(
      text: TextSpan(
        text: ampm,
        style: TextStyle(
          fontFamily: 'Plus Jakarta Sans',
          fontSize: 7.5 * s,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2 * s,
          color: Aurora.accentGreen.withValues(alpha: 0.75),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final double gap = 1.5 * s;
    final double blockH = timeTp.height + ampmTp.height + gap;
    final double top = c.dy - blockH / 2;
    timeTp.paint(canvas, Offset(c.dx - timeTp.width / 2, top));
    ampmTp.paint(
      canvas,
      Offset(c.dx - ampmTp.width / 2, top + timeTp.height + gap),
    );
  }

  @override
  bool shouldRepaint(_RadialClockPainter old) => old.time != time;
}
