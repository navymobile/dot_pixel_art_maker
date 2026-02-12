import 'package:flutter/material.dart';
import '../../domain/dot_model.dart';

class DotGridItem extends StatelessWidget {
  final DotModel dot;
  final VoidCallback onTap;

  const DotGridItem({super.key, required this.dot, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: Card(
          margin: EdgeInsets.zero, // これがないと余白が表示される
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          color: Colors.transparent, // これがないとデフォルトの色が表示される
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: _PreviewPainter(pixels: dot.pixels),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  final List<int> pixels;

  _PreviewPainter({required this.pixels});

  @override
  void paint(Canvas canvas, Size size) {
    // 16x16 grid
    final double cellSize = size.width / 16;

    // Draw background (checkerboard not strictly needed for preview but nice)
    // Simplify for performance: just white background
    final Paint bgPaint = Paint()..color = Colors.transparent;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    for (int i = 0; i < pixels.length; i++) {
      final colorValue = pixels[i];
      if (colorValue != 0) {
        final x = (i % 16) * cellSize;
        final y = (i ~/ 16) * cellSize;

        final paint = Paint()
          ..color = Color(colorValue)
          ..style = PaintingStyle.fill;

        // Use drawRect for crisp pixels
        canvas.drawRect(Rect.fromLTWH(x, y, cellSize, cellSize), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PreviewPainter oldDelegate) {
    return oldDelegate.pixels != pixels;
  }
}
