import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared surfaces for the user-selected glass visual system.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool blur;
  final Color? tint;
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 24,
    this.blur = true,
    this.tint,
  });
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: dark
            ? [
                const Color(0xFF8899B1).withValues(alpha: .28),
                const Color(0xFF172332).withValues(alpha: .68),
                const Color(0xFF45596D).withValues(alpha: .32),
              ]
            : [
                Colors.white.withValues(alpha: .82),
                const Color(0xFFF7FAFF).withValues(alpha: .58),
                Colors.white.withValues(alpha: .65),
              ],
      ),
      border: Border.all(
        color: dark
            ? Colors.white.withValues(alpha: .23)
            : Colors.white.withValues(alpha: .94),
      ),
    );
    final content = DecoratedBox(
      decoration: decoration,
      child: ColoredBox(
        color: tint ?? Colors.transparent,
        child: Material(
          color: Colors.transparent,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: dark
                ? Colors.black.withValues(alpha: .16)
                : const Color(0xFF6683B2).withValues(alpha: .10),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: blur
            ? BackdropFilter.grouped(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: content,
              )
            : content,
      ),
    );
  }
}

class FinanceBackdrop extends StatelessWidget {
  final Widget child;
  const FinanceBackdrop({super.key, required this.child});
  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Theme.of(context).brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
      statusBarBrightness: Theme.of(context).brightness,
      systemNavigationBarColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0A1726)
          : const Color(0xFFE8EFFB),
      systemNavigationBarIconBrightness:
          Theme.of(context).brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
    ),
    child: BackdropGroup(
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: FinanceBackdropPainter(
                Theme.of(context).brightness == Brightness.dark,
              ),
            ),
          ),
          child,
        ],
      ),
    ),
  );
}

class FinanceBackdropPainter extends CustomPainter {
  final bool dark;
  FinanceBackdropPainter(this.dark);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final w = size.width, h = size.height;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF152130), Color(0xFF070F19), Color(0xFF0A1726)]
              : const [Color(0xFFF7F9FE), Color(0xFFE8EFFB), Color(0xFFDEE9F8)],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(.95, .1),
          radius: 1,
          colors: [
            (dark ? const Color(0xFF087AF0) : const Color(0xFF8FBFFF))
                .withValues(alpha: dark ? .17 : .22),
            Colors.transparent,
          ],
        ).createShader(rect),
    );
    final wave = Path()
      ..moveTo(w * 1.14, h * .06)
      ..cubicTo(w * .83, h * .05, w * .66, h * .32, w * .80, h * .49)
      ..cubicTo(w * .98, h * .73, w * .58, h * .78, w * .49, h * 1.06)
      ..lineTo(w * 1.2, h * 1.08)
      ..close();
    canvas.drawPath(
      wave,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: dark
              ? [
                  const Color(0xFF6CB8FF).withValues(alpha: .40),
                  const Color(0xFF00438A).withValues(alpha: .14),
                  const Color(0xFF0A111C).withValues(alpha: .05),
                ]
              : [
                  Colors.white.withValues(alpha: .73),
                  const Color(0xFF9DC4FA).withValues(alpha: .26),
                  Colors.white.withValues(alpha: .11),
                ],
        ).createShader(rect),
    );
    final edge = Path()
      ..moveTo(w * 1.14, h * .06)
      ..cubicTo(w * .83, h * .05, w * .66, h * .32, w * .80, h * .49)
      ..cubicTo(w * .98, h * .73, w * .58, h * .78, w * .49, h * 1.06);
    canvas.drawPath(
      edge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..shader = LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            Colors.white.withValues(alpha: dark ? .43 : .90),
            (dark ? const Color(0xFF2187EF) : Colors.white).withValues(
              alpha: .05,
            ),
          ],
        ).createShader(rect),
    );
    final lower = Path()
      ..moveTo(-w * .15, h * .93)
      ..cubicTo(w * .28, h * .78, w * .37, h * 1.09, w * .95, h * .97)
      ..lineTo(w * 1.1, h * 1.3)
      ..lineTo(-w * .2, h * 1.3)
      ..close();
    canvas.drawPath(
      lower,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            (dark ? const Color(0xFF2687E8) : Colors.white).withValues(
              alpha: dark ? .13 : .65,
            ),
            Colors.transparent,
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(FinanceBackdropPainter oldDelegate) =>
      oldDelegate.dark != dark;
}

class BalanceWavePainter extends CustomPainter {
  final bool dark;
  BalanceWavePainter(this.dark);
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, rect = Offset.zero & size;
    final shapes = [
      Path()
        ..moveTo(w * .51, h * 1.1)
        ..cubicTo(w * .73, h * .18, w * .82, h * .56, w * 1.04, h * .27)
        ..lineTo(w * 1.1, h * 1.2)
        ..close(),
      Path()
        ..moveTo(w * .63, h * 1.1)
        ..cubicTo(w * .75, h * .54, w * .84, h * .23, w * 1.05, h * .73)
        ..lineTo(w * 1.1, h * 1.2)
        ..close(),
    ];
    for (var i = 0; i < shapes.length; i++) {
      canvas.drawPath(
        shapes[i],
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? [
                    const Color(0xFF55CBFF).withValues(alpha: .82),
                    const Color(0xFF087BFF).withValues(alpha: .56),
                    const Color(0xFF00365F).withValues(alpha: .45),
                  ]
                : [
                    const Color(0xFFE5F3FF).withValues(alpha: .9),
                    const Color(0xFF8EC5FF).withValues(alpha: .57),
                    const Color(0xFFC9DCFF).withValues(alpha: .28),
                  ],
          ).createShader(rect),
      );
      canvas.drawPath(
        shapes[i],
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: dark ? .48 : .9),
      );
    }
  }

  @override
  bool shouldRepaint(BalanceWavePainter oldDelegate) =>
      oldDelegate.dark != dark;
}

class FinanceLogo extends StatelessWidget {
  final double size;
  const FinanceLogo({super.key, this.size = 44});
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size * .28),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF91D4FF), Color(0xFF2A90FF), Color(0xFF1162E9)],
      ),
      border: Border.all(color: Colors.white.withValues(alpha: .5)),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF1A78EF).withValues(alpha: .20),
          blurRadius: 14,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Icon(Icons.bar_chart_rounded, color: Colors.white, size: size * .68),
  );
}

class GlassIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const GlassIcon(this.icon, {super.key, required this.color, this.size = 40});
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size * .32),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [color.withValues(alpha: .21), color.withValues(alpha: .06)],
      ),
      border: Border.all(color: Colors.white.withValues(alpha: .20)),
    ),
    child: Icon(icon, size: size * .54, color: color),
  );
}

class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
  @override
  Widget build(BuildContext context) => GlassPanel(
    radius: 24,
    padding: EdgeInsets.zero,
    blur: false,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 21),
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
    ),
  );
}
