import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../app/theme/aurora_colors.dart';

/// Type of an entry orbiting the clock — drives the dot's color.
enum ClockEntryType { meal, symptom, mood }

/// One entry placed around the dial by its time of day.
class ClockEntry {
  /// Stable id correlating the dot to its list row (meal/symptom id).
  final String id;
  final DateTime time;
  final ClockEntryType type;

  /// Short display name shown in the tap popup (meal name / symptom type).
  final String label;

  const ClockEntry({
    required this.id,
    required this.time,
    required this.type,
    required this.label,
  });

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

  /// Currently-selected entry id (controlled). Its dot glows and shows a popup.
  final String? selectedId;

  /// Called when a dot is tapped (with its id) or the popup is dismissed (null).
  final ValueChanged<String?>? onSelect;

  /// Side length of the (square) clock zone in logical pixels.
  final double size;

  const RadialClock({
    super.key,
    this.time,
    this.entries = const [],
    this.selectedId,
    this.onSelect,
    this.size = 278,
  });

  static const double designSize = 278;
  static const double _rAmOrbit = 60;
  static const double _rPmOrbit = 118;

  @override
  Widget build(BuildContext context) {
    final DateTime t = time ?? DateTime.now();
    final double s = size / designSize;
    ClockEntry? selected;
    for (final e in entries) {
      if (e.id == selectedId) selected = e;
    }
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _RadialClockPainter(time: t)),
          ),
          for (final e in entries) _positionDot(e, s, e.id == selectedId),
          // Curved arc name/time tags above the dots (spec §3). Drawn above the
          // dots, below the popup. pointer-events: none (spec) so dot taps pass
          // through.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ArcLabelsPainter(
                  entries: entries,
                  selectedId: selectedId,
                ),
              ),
            ),
          ),
          if (selected != null) _positionPopup(selected, s),
        ],
      ),
    );
  }

  Offset _dotCenter(ClockEntry e, double s) {
    final double r = (e.isAm ? _rAmOrbit : _rPmOrbit) * s;
    final double rad = e.angleDeg * math.pi / 180;
    return Offset(
      size / 2 + r * math.sin(rad),
      size / 2 - r * math.cos(rad),
    );
  }

  Widget _positionDot(ClockEntry e, double s, bool selected) {
    final double dotSize = (e.isAm ? 26.0 : 34.0) * s;
    final Offset c = _dotCenter(e, s);
    return Positioned(
      left: c.dx - dotSize / 2,
      top: c.dy - dotSize / 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelect?.call(selected ? null : e.id),
        child: _OrbitDot(
          type: e.type,
          isAm: e.isAm,
          size: dotSize,
          selected: selected,
        ),
      ),
    );
  }

  Widget _positionPopup(ClockEntry e, double s) {
    final double dotSize = (e.isAm ? 26.0 : 34.0) * s;
    final Offset c = _dotCenter(e, s);
    // Sit just below the dot, centered horizontally over it.
    return Positioned(
      left: c.dx,
      top: c.dy + dotSize / 2 + 8 * s,
      child: FractionalTranslation(
        translation: const Offset(-0.5, 0),
        child: _TapPopup(
          entry: e,
          scale: s,
          onDismiss: () => onSelect?.call(null),
        ),
      ),
    );
  }
}

/// A single orbit marker — a bordered, softly-filled circle colored by entry
/// type and AM/PM zone. When [selected], it gains an emerald glow ring.
class _OrbitDot extends StatelessWidget {
  final ClockEntryType type;
  final bool isAm;
  final double size;
  final bool selected;

  const _OrbitDot({
    required this.type,
    required this.isAm,
    required this.size,
    this.selected = false,
  });

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
        border: Border.all(
          color: selected ? Aurora.accentGreen.withValues(alpha: 0.7) : border,
          width: 1.5,
        ),
        // Aurora selected glow (arc-labels spec §4).
        boxShadow: selected
            ? const [
                BoxShadow(color: Color(0x2E34D399), blurRadius: 0, spreadRadius: 5),
                BoxShadow(color: Color(0x1234D399), blurRadius: 0, spreadRadius: 9),
                BoxShadow(color: Color(0x4D34D399), blurRadius: 18),
              ]
            : null,
      ),
    );
  }
}

/// Floating card shown above the entry list... actually below the selected dot,
/// with the entry's name + time and a dismiss affordance (arc-labels spec §4).
class _TapPopup extends StatelessWidget {
  final ClockEntry entry;
  final double scale;
  final VoidCallback onDismiss;

  const _TapPopup({
    required this.entry,
    required this.scale,
    required this.onDismiss,
  });

  String get _timeLabel {
    final int h = entry.time.hour % 12 == 0 ? 12 : entry.time.hour % 12;
    final String m = entry.time.minute.toString().padLeft(2, '0');
    final String ap = entry.time.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

  @override
  Widget build(BuildContext context) {
    final double s = scale;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Upward arrow pointing at the dot.
        CustomPaint(size: Size(14 * s, 8 * s), painter: _ArrowPainter()),
        Container(
          padding: EdgeInsets.fromLTRB(10 * s, 9 * s, 13 * s, 9 * s),
          decoration: BoxDecoration(
            color: const Color(0xF20D2235),
            borderRadius: BorderRadius.circular(13 * s),
            border: Border.all(
              color: Aurora.accentGreen.withValues(alpha: 0.35),
              width: 1.5,
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 6)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.label,
                    style: TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 12 * s,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: Aurora.textPrimary,
                    ),
                  ),
                  SizedBox(height: 2 * s),
                  Text(
                    _timeLabel,
                    style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 9 * s,
                      color: Aurora.accentGreen.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
              SizedBox(width: 8 * s),
              GestureDetector(
                onTap: onDismiss,
                child: Text(
                  '×',
                  style: TextStyle(
                    fontSize: 14 * s,
                    color: Aurora.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final border = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      border,
      Paint()..color = Aurora.accentGreen.withValues(alpha: 0.4),
    );
    // inner fill slightly below to leave a thin border edge
    final fill = Path()
      ..moveTo(size.width / 2, 2)
      ..lineTo(2, size.height)
      ..lineTo(size.width - 2, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = const Color(0xFF0D2235));
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => false;
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

/// Paints curved name/time tags hugging each orbit dot (Hearty UI Design Guide
/// arc-labels companion §3). Flutter has no SVG `textPath`, so each glyph is laid
/// out and rotated along a per-dot arc by hand.
class _ArcLabelsPainter extends CustomPainter {
  final List<ClockEntry> entries;
  final String? selectedId;

  _ArcLabelsPainter({required this.entries, this.selectedId});

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.shortestSide / RadialClock.designSize;
    final Offset center = Offset(size.width / 2, size.height / 2);
    for (final e in entries) {
      final bool isAm = e.isAm;
      final double orbit = (isAm ? 60.0 : 118.0) * s;
      final double rad = e.angleDeg * math.pi / 180;
      final Offset dot = Offset(
        center.dx + orbit * math.sin(rad),
        center.dy - orbit * math.cos(rad),
      );
      // Text arc just outside the dot (AM r≈18, PM r≈21 — dot radius + margin).
      final double arcR = (isAm ? 18.0 : 21.0) * s;
      // Dots near the top use a bottom arc so the label doesn't exit the zone.
      final bool topArc = !_nearTop(e.angleDeg);
      final style = TextStyle(
        fontFamily: 'Plus Jakarta Sans',
        fontSize: (isAm ? 7.5 : 8.0) * s,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3 * s,
        color: _labelColor(e, e.id == selectedId),
      );
      _paintArcText(canvas, dot, arcR, _labelFor(e), style, topArc: topArc);
    }
  }

  /// True when the dot sits within ±45° of 12 o'clock.
  bool _nearTop(double deg) {
    final double a = deg % 360;
    return a <= 45 || a >= 315;
  }

  String _labelFor(ClockEntry e) {
    final int h = e.time.hour % 12 == 0 ? 12 : e.time.hour % 12;
    final String time = '$h:${e.time.minute.toString().padLeft(2, '0')}';
    // PM meals show a short food name when it fits; everything else shows time.
    if (!e.isAm && e.type == ClockEntryType.meal && e.label.length <= 7) {
      return e.label;
    }
    return time;
  }

  Color _labelColor(ClockEntry e, bool selected) {
    if (e.isAm) {
      return e.type == ClockEntryType.symptom
          ? Aurora.accentRed.withValues(alpha: 0.8)
          : Aurora.accentViolet.withValues(alpha: 0.85);
    }
    return switch (e.type) {
      ClockEntryType.symptom => Aurora.accentRed.withValues(alpha: 0.7),
      ClockEntryType.mood => Aurora.accentVioletLight.withValues(alpha: 0.65),
      ClockEntryType.meal => Aurora.accentGreen.withValues(
        alpha: selected ? 0.9 : 0.65,
      ),
    };
  }

  void _paintArcText(
    Canvas canvas,
    Offset center,
    double radius,
    String text,
    TextStyle style, {
    required bool topArc,
  }) {
    final painters = [
      for (final ch in text.characters)
        TextPainter(
          text: TextSpan(text: ch, style: style),
          textDirection: TextDirection.ltr,
        )..layout(),
    ];
    final double totalW = painters.fold(0.0, (a, p) => a + p.width);
    if (totalW == 0) return;
    final double totalAngle = totalW / radius;
    double a = -totalAngle / 2; // signed angle from the apex, left → right
    for (final tp in painters) {
      final double ga = tp.width / radius;
      final double mid = a + ga / 2;
      canvas.save();
      if (topArc) {
        canvas.translate(
          center.dx + radius * math.sin(mid),
          center.dy - radius * math.cos(mid),
        );
        canvas.rotate(mid);
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height));
      } else {
        canvas.translate(
          center.dx + radius * math.sin(mid),
          center.dy + radius * math.cos(mid),
        );
        canvas.rotate(-mid);
        tp.paint(canvas, Offset(-tp.width / 2, 0));
      }
      canvas.restore();
      a += ga;
    }
  }

  @override
  bool shouldRepaint(_ArcLabelsPainter old) =>
      old.entries != entries || old.selectedId != selectedId;
}
