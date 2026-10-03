import 'package:flutter/material.dart';

String arcadeGameName(String id) => id
    .split(RegExp(r'[-_]'))
    .where((word) => word.isNotEmpty)
    .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
    .join(' ');

Color arcadeGameColor(String id) {
  if (id == 'chess') return const Color(0xffd8acff);
  if (id == 'pong') return const Color(0xff55e6da);
  const colors = [Color(0xffffab66), Color(0xff78b4ff), Color(0xffff87c2)];
  return colors[id.codeUnits.fold<int>(0, (a, b) => a + b) % colors.length];
}

/// Local vector artwork stays crisp in both the lobby list and game picker.
/// Unknown games receive a colourful controller cover until bespoke art exists.
class ArcadeGameArtwork extends StatelessWidget {
  const ArcadeGameArtwork({super.key, required this.gameId, this.radius = 16});
  final String gameId;
  final double radius;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CustomPaint(
        painter: _GamePainter(gameId),
        child: gameId == 'chess' || gameId == 'pong'
            ? const SizedBox.expand()
            : Center(
                child: Icon(
                  Icons.sports_esports_rounded,
                  color: arcadeGameColor(gameId),
                  size: 64,
                ),
              ),
      ),
    ),
  );
}

class _GamePainter extends CustomPainter {
  const _GamePainter(this.id);
  final String id;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final accent = arcadeGameColor(id);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: id == 'chess'
              ? const [Color(0xff613e91), Color(0xff241836)]
              : id == 'pong'
              ? const [Color(0xff134653), Color(0xff102a3b)]
              : [accent.withValues(alpha: .4), const Color(0xff25223d)],
        ).createShader(rect),
    );
    canvas.drawCircle(
      Offset(size.width * .8, size.height * .2),
      size.longestSide * .38,
      Paint()..color = accent.withValues(alpha: .08),
    );
    canvas.save();
    canvas.translate(
      (size.width - size.shortestSide) / 2,
      (size.height - size.shortestSide) / 2,
    );
    canvas.scale(size.shortestSide / 100);
    if (id == 'chess') {
      for (var y = 0; y < 5; y++) {
        for (var x = 0; x < 5; x++) {
          if ((x + y).isEven) {
            canvas.drawRect(
              Rect.fromLTWH(x * 20, y * 20, 20, 20),
              Paint()..color = Colors.white.withValues(alpha: .055),
            );
          }
        }
      }
      final piece = Path()
        ..moveTo(30, 74)
        ..lineTo(70, 74)
        ..lineTo(66, 66)
        ..lineTo(60, 62)
        ..lineTo(57, 45)
        ..lineTo(66, 33)
        ..lineTo(64, 28)
        ..lineTo(54, 33)
        ..lineTo(50, 23)
        ..lineTo(46, 33)
        ..lineTo(36, 28)
        ..lineTo(34, 33)
        ..lineTo(43, 45)
        ..lineTo(40, 62)
        ..lineTo(34, 66)
        ..close();
      canvas.drawShadow(piece, Colors.black, 5, false);
      canvas.drawPath(
        piece,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xffffefcc), Color(0xffe7ae68)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(const Rect.fromLTWH(30, 23, 40, 51)),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(28, 76, 44, 6),
          const Radius.circular(3),
        ),
        Paint()..color = const Color(0xffffdfad),
      );
      canvas.drawLine(
        const Offset(50, 12),
        const Offset(50, 22),
        Paint()
          ..color = const Color(0xffffdfad)
          ..strokeWidth = 3,
      );
      canvas.drawLine(
        const Offset(46, 16),
        const Offset(54, 16),
        Paint()
          ..color = const Color(0xffffdfad)
          ..strokeWidth = 3,
      );
    } else if (id == 'pong') {
      final grid = Paint()
        ..color = accent.withValues(alpha: .09)
        ..strokeWidth = .5;
      for (var i = 10.0; i < 100; i += 10) {
        canvas.drawLine(Offset(i, 0), Offset(i, 100), grid);
        canvas.drawLine(Offset(0, i), Offset(100, i), grid);
      }
      for (var y = 12.0; y < 90; y += 12) {
        canvas.drawLine(
          Offset(50, y),
          Offset(50, y + 6),
          Paint()
            ..color = Colors.white.withValues(alpha: .22)
            ..strokeWidth = 1.5,
        );
      }
      void paddle(Rect r, Color color) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(r.inflate(2), const Radius.circular(4)),
          Paint()..color = color.withValues(alpha: .18),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(2)),
          Paint()..color = color,
        );
      }

      paddle(const Rect.fromLTWH(18, 49, 5, 27), const Color(0xff55e6da));
      paddle(const Rect.fromLTWH(77, 22, 5, 27), const Color(0xffff82ca));
      for (var i = 0; i < 4; i++) {
        canvas.drawCircle(
          Offset(39 + i * 6, 59 - i * 4),
          2 + i * .35,
          Paint()..color = Colors.white.withValues(alpha: .08 + i * .07),
        );
      }
      canvas.drawCircle(
        const Offset(64, 42),
        7,
        Paint()..color = accent.withValues(alpha: .15),
      );
      canvas.drawCircle(
        const Offset(64, 42),
        3.5,
        Paint()..color = Colors.white,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GamePainter oldDelegate) => oldDelegate.id != id;
}
