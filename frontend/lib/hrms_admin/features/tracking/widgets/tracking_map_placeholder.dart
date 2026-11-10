import 'package:flutter/material.dart';
import 'package:hrms_design_system/hrms_design_system.dart';

/// Static placeholder for the live tracking map — pins + street labels
/// laid out to match the reference screen. Real map tiles and live pin
/// positions are wired once /tracking/live (Section 6) is connected;
/// this keeps the layout and visual weight correct in the meantime.
class TrackingMapPlaceholder extends StatelessWidget {
  const TrackingMapPlaceholder({super.key});

  static const _pins = [
    Offset(0.18, 0.15),
    Offset(0.52, 0.12),
    Offset(0.78, 0.22),
    Offset(0.58, 0.38),
    Offset(0.15, 0.55),
    Offset(0.42, 0.62),
    Offset(0.68, 0.62),
    Offset(0.52, 0.85),
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Container(
          color: const Color(0xFFF1EFE9),
          child: Stack(
            children: [
              CustomPaint(painter: _RoadGridPainter(), size: Size.infinite),
              for (final p in _pins)
                Align(
                  alignment: Alignment(p.dx * 2 - 1, p.dy * 2 - 1),
                  child: const Icon(Icons.location_on,
                      color: Color(0xFFF97316), size: 30),
                ),
              Positioned(
                left: 12,
                bottom: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8)),
                  child: const Text('Map view — live tiles pending API',
                      style:
                          TextStyle(fontSize: 11, color: HrmsColors.textMuted)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoadGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE2DFD5)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += size.width / 8) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += size.height / 6) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
