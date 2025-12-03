import 'dart:math';
import 'package:flutter/material.dart';

class DotCircleLoader extends StatefulWidget {
  final double size;
  final Color color;

  const DotCircleLoader({
    super.key,
    this.size = 50,
    this.color = Colors.blue,
  });

  @override
  State<DotCircleLoader> createState() => _DotCircleLoaderState();
}

class _DotCircleLoaderState extends State<DotCircleLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(); // 🔥 repeat forever — FIX
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, child) {
        return Transform.rotate(
          angle: _controller.value * 2 * pi,
          child: child,
        );
      },
      child: CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _DotCirclePainter(widget.color),
      ),
    );
  }
}

class _DotCirclePainter extends CustomPainter {
  final Color color;

  _DotCirclePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width * 0.35;
    final paint = Paint()..color = color;

    for (int i = 0; i < 8; i++) {
      final angle = (pi / 4) * i;
      final dx = center.dx + radius * cos(angle);
      final dy = center.dy + radius * sin(angle);

      canvas.drawCircle(Offset(dx, dy), 4, paint);
    }
  }

  @override
  bool shouldRepaint(_) => true;
}
