import 'package:flutter/material.dart';

/// One shared gold coin symbol used wherever coin amounts appear.
class CoinIcon extends StatelessWidget {
  const CoinIcon({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _CoinIconPainter()),
      );
}

class _CoinIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * .46;
    final gold = Paint()..color = const Color(0xFFFFD54F)..isAntiAlias = true;
    final rim = Paint()
      ..color = const Color(0xFFB8860B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .07
      ..isAntiAlias = true;
    final inner = Paint()
      ..color = const Color(0xFFFFE082)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .045
      ..isAntiAlias = true;
    canvas.drawCircle(center, radius, gold);
    canvas.drawCircle(center, radius * .86, rim);
    canvas.drawCircle(center, radius * .70, inner);
    final detail = Paint()
      ..color = const Color(0xFF8A6500)
      ..strokeWidth = size.width * .07
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final path = Path()
      ..moveTo(size.width * .32, size.height * .35)
      ..lineTo(size.width * .68, size.height * .35)
      ..moveTo(size.width * .32, size.height * .50)
      ..lineTo(size.width * .62, size.height * .50)
      ..moveTo(size.width * .32, size.height * .65)
      ..lineTo(size.width * .55, size.height * .65);
    canvas.drawPath(path, detail);
  }

  @override
  bool shouldRepaint(covariant _CoinIconPainter oldDelegate) => false;
}
