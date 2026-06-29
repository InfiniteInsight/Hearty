import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../app/theme/aurora_colors.dart';

/// Type of an entry orbiting the clock — drives the dot's color.
enum ClockEntryType { meal, symptom, mood }

/// Emoji shown inside an orbit dot / the tap popup, by type.
String clockEntryEmoji(ClockEntryType type) => switch (type) {
      ClockEntryType.meal => '🍽️',
      ClockEntryType.symptom => '🤢',
      ClockEntryType.mood => '😊',
    };

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

  /// Currently-selected entry ids (controlled). All entries of the tapped
  /// bubble are selected together; their dots glow and the popup lists them.
  final Set<String> selectedIds;

  /// Called when a bubble is tapped (with all its entry ids) or the popup is
  /// dismissed (empty set).
  final ValueChanged<Set<String>>? onSelect;

  /// Side length of the (square) clock zone in logical pixels.
  final double size;

  const RadialClock({
    super.key,
    this.time,
    this.entries = const [],
    this.selectedIds = const {},
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
    // Entries logged close in time (same ring, overlapping dots) merge into one
    // split bubble so a meal + its symptom don't stack on top of each other.
    final clusters = _clusterEntries(entries);
    _Cluster? selectedCluster;
    for (final c in clusters) {
      if (c.entries.any((e) => selectedIds.contains(e.id))) selectedCluster = c;
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
          for (final c in clusters) _positionBubble(c, s),
          // Curved arc name/time tags above the dots (spec §3). pointer-events:
          // none (spec) so bubble taps pass through.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ArcLabelsPainter(
                  clusters: clusters,
                  selectedIds: selectedIds,
                ),
              ),
            ),
          ),
          if (selectedCluster != null) _positionPopup(selectedCluster, s),
        ],
      ),
    );
  }

  Offset _clusterCenter(_Cluster c, double s) {
    final double r = (c.isAm ? _rAmOrbit : _rPmOrbit) * s;
    final double rad = c.angleDeg * math.pi / 180;
    return Offset(
      size / 2 + r * math.sin(rad),
      size / 2 - r * math.cos(rad),
    );
  }

  Widget _positionBubble(_Cluster c, double s) {
    final double dotSize = (c.isAm ? 26.0 : 34.0) * s;
    final Offset center = _clusterCenter(c, s);
    final bool isSel = c.entries.any((e) => selectedIds.contains(e.id));
    return Positioned(
      left: center.dx - dotSize / 2,
      top: center.dy - dotSize / 2,
      child: _OrbitBubble(
        entries: c.entries,
        isAm: c.isAm,
        size: dotSize,
        selected: isSel,
        // Tap anywhere on the bubble → select all its entries (or deselect).
        onTap: () => onSelect?.call(
          isSel ? <String>{} : {for (final e in c.entries) e.id},
        ),
      ),
    );
  }

  Widget _positionPopup(_Cluster c, double s) {
    final double dotSize = (c.isAm ? 26.0 : 34.0) * s;
    final Offset center = _clusterCenter(c, s);
    // Sit just below the bubble, centered horizontally over it.
    return Positioned(
      left: center.dx,
      top: center.dy + dotSize / 2 + 8 * s,
      child: FractionalTranslation(
        translation: const Offset(-0.5, 0),
        child: _TapPopup(
          entries: c.entries,
          scale: s,
          onDismiss: () => onSelect?.call(<String>{}),
        ),
      ),
    );
  }
}

/// Type ordering so a cluster's wedges lay out consistently (meal first).
const Map<ClockEntryType, int> _typeOrder = {
  ClockEntryType.meal: 0,
  ClockEntryType.symptom: 1,
  ClockEntryType.mood: 2,
};

/// One or more entries sharing a spot on the dial. A single entry renders as a
/// normal dot; multiple render as a split (pie) bubble.
class _Cluster {
  final List<ClockEntry> entries; // sorted by type
  final bool isAm;
  final double angleDeg; // mean angle of the group

  const _Cluster(this.entries, this.isAm, this.angleDeg);

  bool contains(String? id) => entries.any((e) => e.id == id);
}

/// Groups entries that would visually overlap (same ring, angular gap smaller
/// than a dot's angular width) into clusters, so they can share a split bubble.
List<_Cluster> _clusterEntries(List<ClockEntry> entries) {
  List<_Cluster> ring(Iterable<ClockEntry> raw, double orbitR, double dotSize) {
    final es = raw.toList()..sort((a, b) => a.angleDeg.compareTo(b.angleDeg));
    if (es.isEmpty) return const [];
    final double thresholdDeg = (dotSize / orbitR) * 180 / math.pi;
    final groups = <List<ClockEntry>>[
      [es.first]
    ];
    for (var i = 1; i < es.length; i++) {
      if (es[i].angleDeg - groups.last.last.angleDeg <= thresholdDeg) {
        groups.last.add(es[i]);
      } else {
        groups.add([es[i]]);
      }
    }
    return [
      for (final g in groups)
        _Cluster(
          [...g]..sort((a, b) => _typeOrder[a.type]!.compareTo(_typeOrder[b.type]!)),
          g.first.isAm,
          g.map((e) => e.angleDeg).reduce((a, b) => a + b) / g.length,
        ),
    ];
  }

  return [
    ...ring(entries.where((e) => e.isAm), 60, 26),
    ...ring(entries.where((e) => !e.isAm), 118, 34),
  ];
}

/// An orbit bubble for one cluster. A single entry renders as a colored disc; a
/// cluster of N renders as a circle split into N colored wedges. Each wedge is
/// independently tappable — tapping it selects that entry.
class _OrbitBubble extends StatelessWidget {
  final List<ClockEntry> entries; // sorted by type
  final bool isAm;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  const _OrbitBubble({
    required this.entries,
    required this.isAm,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  static (Color, Color) colorsFor(ClockEntryType type, bool isAm) =>
      switch ((type, isAm)) {
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

  /// Wedge i spans [π/2 + i·sweep, +sweep] (canvas angles: 0 = 3 o'clock,
  /// positive = clockwise). With this base, for N=2 wedge 0 is the left half.
  static double wedgeStart(int i, int n) => math.pi / 2 + i * (2 * math.pi / n);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: CustomPaint(
        size: Size.square(size),
        painter: _BubblePainter(
          entries: entries,
          isAm: isAm,
          selected: selected,
        ),
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  final List<ClockEntry> entries;
  final bool isAm;
  final bool selected;

  _BubblePainter({
    required this.entries,
    required this.isAm,
    required this.selected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = Offset(size.width / 2, size.height / 2);
    final double r = size.width / 2;
    final int n = entries.length;

    // Aurora selected glow (arc-labels spec §4).
    if (selected) {
      canvas.drawCircle(c, r + 5, Paint()..color = const Color(0x2E34D399));
      canvas.drawCircle(
        c,
        r + 2,
        Paint()
          ..color = const Color(0x4D34D399)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }

    if (n == 1) {
      final (fill, border) = _OrbitBubble.colorsFor(entries.first.type, isAm);
      canvas.drawCircle(c, r, Paint()..color = fill);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = selected
              ? Aurora.accentGreen.withValues(alpha: 0.7)
              : border,
      );
      _emoji(canvas, entries.first.type, c, size.width * 0.5);
      return;
    }

    final double sweep = 2 * math.pi / n;
    final rect = Rect.fromCircle(center: c, radius: r);
    for (var i = 0; i < n; i++) {
      final (fill, border) = _OrbitBubble.colorsFor(entries[i].type, isAm);
      final double start = _OrbitBubble.wedgeStart(i, n);
      // Filled wedge.
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..arcTo(rect, start, sweep, false)
        ..close();
      canvas.drawPath(path, Paint()..color = fill);
      // Colored rim arc for the wedge (emerald-bright if this entry is selected).
      canvas.drawArc(
        rect.deflate(0.75),
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = border,
      );
      // Emoji at the wedge's mid-angle.
      final double mid = start + sweep / 2;
      _emoji(
        canvas,
        entries[i].type,
        c + Offset(math.cos(mid), math.sin(mid)) * (r * 0.5),
        size.width * 0.30,
      );
    }
    // Subtle dividers between wedges.
    for (var i = 0; i < n; i++) {
      final double a = _OrbitBubble.wedgeStart(i, n);
      canvas.drawLine(
        c,
        c + Offset(math.cos(a), math.sin(a)) * r,
        Paint()
          ..strokeWidth = 1.0
          ..color = const Color(0x33FFFFFF),
      );
    }
  }

  void _emoji(Canvas canvas, ClockEntryType type, Offset center, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(
        text: clockEntryEmoji(type),
        style: TextStyle(fontSize: fontSize, height: 1.0),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.entries != entries || old.selected != selected;
}

/// Floating card shown below a tapped bubble, listing its entries (a meal +
/// symptom logged together show stacked) with a dismiss affordance.
class _TapPopup extends StatelessWidget {
  final List<ClockEntry> entries;
  final double scale;
  final VoidCallback onDismiss;

  const _TapPopup({
    required this.entries,
    required this.scale,
    required this.onDismiss,
  });

  static String _timeLabel(ClockEntry e) {
    final int h = e.time.hour % 12 == 0 ? 12 : e.time.hour % 12;
    final String m = e.time.minute.toString().padLeft(2, '0');
    final String ap = e.time.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

  @override
  Widget build(BuildContext context) {
    final double s = scale;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Upward arrow pointing at the bubble.
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < entries.length; i++) ...[
                    if (i > 0) SizedBox(height: 7 * s),
                    _entryRow(entries[i], s),
                  ],
                ],
              ),
              SizedBox(width: 8 * s),
              GestureDetector(
                onTap: onDismiss,
                child: Text(
                  '×',
                  style: TextStyle(fontSize: 14 * s, color: Aurora.textMuted),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _entryRow(ClockEntry e, double s) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(clockEntryEmoji(e.type), style: TextStyle(fontSize: 18 * s, height: 1.0)),
        SizedBox(width: 8 * s),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              e.label,
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
              _timeLabel(e),
              style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 9 * s,
                color: Aurora.accentGreen.withValues(alpha: 0.7),
              ),
            ),
          ],
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
  final List<_Cluster> clusters;
  final Set<String> selectedIds;

  _ArcLabelsPainter({required this.clusters, this.selectedIds = const {}});

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.shortestSide / RadialClock.designSize;
    final Offset center = Offset(size.width / 2, size.height / 2);
    for (final c in clusters) {
      final bool isAm = c.isAm;
      final double orbit = (isAm ? 60.0 : 118.0) * s;
      final double rad = c.angleDeg * math.pi / 180;
      final Offset dot = Offset(
        center.dx + orbit * math.sin(rad),
        center.dy - orbit * math.cos(rad),
      );
      // Text arc just outside the dot (AM r≈18, PM r≈21 — dot radius + margin).
      final double arcR = (isAm ? 18.0 : 21.0) * s;
      // Dots near the top use a bottom arc so the label doesn't exit the zone.
      final bool topArc = !_nearTop(c.angleDeg);
      final style = TextStyle(
        fontFamily: 'Plus Jakarta Sans',
        fontSize: (isAm ? 7.5 : 8.0) * s,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3 * s,
        color: _labelColor(c),
      );
      _paintArcText(canvas, dot, arcR, _labelFor(c), style, topArc: topArc);
    }
  }

  /// True when the dot sits within ±45° of 12 o'clock.
  bool _nearTop(double deg) {
    final double a = deg % 360;
    return a <= 45 || a >= 315;
  }

  String _labelFor(_Cluster c) {
    final e = c.entries.first;
    final int h = e.time.hour % 12 == 0 ? 12 : e.time.hour % 12;
    final String time = '$h:${e.time.minute.toString().padLeft(2, '0')}';
    // A merged bubble shows just the shared time. A single PM meal shows a short
    // food name when it fits; everything else shows time.
    if (c.entries.length == 1 &&
        !e.isAm &&
        e.type == ClockEntryType.meal &&
        e.label.length <= 7) {
      return e.label;
    }
    return time;
  }

  Color _labelColor(_Cluster c) {
    // Merged bubble → neutral; single entry → its type color.
    if (c.entries.length > 1) {
      return Aurora.textPrimary.withValues(alpha: 0.6);
    }
    final e = c.entries.first;
    final bool selected = selectedIds.contains(e.id);
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
      old.clusters != clusters || old.selectedIds != selectedIds;
}
