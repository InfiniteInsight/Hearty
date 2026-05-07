import 'dart:math' as math;
import 'package:flutter/material.dart';

class WaveformAnimation extends StatefulWidget {
  const WaveformAnimation({super.key});

  @override
  State<WaveformAnimation> createState() => _WaveformAnimationState();
}

class _WaveformAnimationState extends State<WaveformAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('waveform_animation'),
      width: 120,
      height: 60,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _WaveformPainter(
              _controller.value,
              Theme.of(context).colorScheme.primary,
            ),
          );
        },
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter(this.progress, this.color);
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const barCount = 12;
    final barWidth = size.width / (barCount * 2 - 1);
    for (var i = 0; i < barCount; i++) {
      final phase = (i / barCount + progress) * math.pi * 2;
      final height = (math.sin(phase).abs() * 0.7 + 0.3) * size.height;
      final x = i * barWidth * 2 + barWidth / 2;
      final top = (size.height - height) / 2;
      canvas.drawLine(Offset(x, top), Offset(x, top + height), paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => old.progress != progress;
}
