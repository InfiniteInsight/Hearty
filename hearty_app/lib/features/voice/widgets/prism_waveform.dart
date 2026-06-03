import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'prism_shader_state.dart';

/// Live voice visualiser: a luminous waveform that behaves like white light
/// through a prism. At silence the three RGB channels coincide into a single
/// calm white beam; as the user speaks the channels split into a centre-pinned
/// chromatic spread that grows taller and faster with volume, while the left
/// and right edges stay white.
///
/// A faithful Flutter port of the approved Canvas-2D prototype
/// (`.superpowers/brainstorm/651807-1779833963/content/voice_shader_live.html`)
/// per `docs/superpowers/specs/2026-06-01-prism-waveform-voice-visualizer.md`.
///
/// Driven by a [Ticker] (one repaint per frame) and wrapped in a
/// [RepaintBoundary] so only the visualiser repaints. [level] is the live mic
/// amplitude as a normalised linear RMS (silence ≈ 0); it is pulled once per
/// frame so audio updates never rebuild the widget tree.
class PrismWaveform extends StatefulWidget {
  const PrismWaveform({super.key, required this.level});

  /// Normalised linear-RMS mic amplitude in roughly 0..1 (silence ≈ 0). Read
  /// each frame; the noise gate + smoothing live in [PrismShaderState].
  final ValueListenable<double> level;

  @override
  State<PrismWaveform> createState() => _PrismWaveformState();
}

class _PrismWaveformState extends State<PrismWaveform>
    with SingleTickerProviderStateMixin {
  final PrismShaderState _shader = PrismShaderState();
  // Bumped each frame to repaint the painter without rebuilding the widget.
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration _) {
    _shader.tick(widget.level.value);
    _frame.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _PrismPainter(_shader, repaint: _frame),
      ),
    );
  }
}

class _Channel {
  const _Channel(this.sign, this.color);
  final int sign;
  final Color color;
}

class _GlowLayer {
  const _GlowLayer(this.widthFraction, this.alpha);

  /// Stroke width as a fraction of canvas width (resolution-independent).
  final double widthFraction;
  final double alpha;
}

class _PrismPainter extends CustomPainter {
  _PrismPainter(this.shader, {required Listenable repaint})
      : super(repaint: repaint);

  final PrismShaderState shader;

  // Near-pure RGB so screen-blend sums to clean white at overlap (spec §3).
  static const List<_Channel> _channels = [
    _Channel(1, Color.fromARGB(255, 255, 28, 28)),
    _Channel(0, Color.fromARGB(255, 28, 255, 28)),
    _Channel(-1, Color.fromARGB(255, 28, 28, 255)),
  ];

  // Glow stack: widest+faintest first, narrowest+brightest last (spec §3).
  static const List<_GlowLayer> _glow = [
    _GlowLayer(0.120, 0.016),
    _GlowLayer(0.050, 0.040),
    _GlowLayer(0.018, 0.110),
    _GlowLayer(0.006, 0.360),
    _GlowLayer(0.0025, 0.780),
    _GlowLayer(0.001, 1.000),
  ];

  // Horizontal sampling step in logical pixels — far fewer points than the
  // prototype's physical-pixel loop, still smooth at this wave frequency.
  static const double _stepPx = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;
    final cy = h / 2;
    final minDim = w < h ? w : h;

    // Opaque black background — the screen blend reconstructs white only on
    // black (spec §6). saveLayer isolates the additive blend to this canvas.
    final bgPaint = Paint()..color = const Color(0xFF000000);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Build one path per channel from the shared phase formula.
    final paths = <Path>[];
    for (final ch in _channels) {
      final path = Path();
      var first = true;
      for (var px = 0.0; px <= w; px += _stepPx) {
        final offset = prismChannelOffset(
          px: px,
          width: w,
          height: h,
          channelSign: ch.sign,
          time: shader.time,
          yScale: shader.yScale,
          distortion: shader.distortion,
          norm: shader.norm,
        );
        final py = cy + offset * (minDim / 2);
        if (first) {
          path.moveTo(px, py);
          first = false;
        } else {
          path.lineTo(px, py);
        }
      }
      paths.add(path);
    }

    // Additive-toward-white blend, isolated in a layer over the black bg.
    canvas.saveLayer(Offset.zero & size, Paint());
    for (var i = 0; i < _channels.length; i++) {
      final color = _channels[i].color;
      for (final g in _glow) {
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..blendMode = BlendMode.screen
          ..strokeWidth = g.widthFraction * w
          ..color = color.withValues(alpha: g.alpha);
        canvas.drawPath(paths[i], paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PrismPainter oldDelegate) => false; // repaint via Listenable
}
