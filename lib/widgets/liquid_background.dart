import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// alienwavegroup.com's animated hero background: the same domain-warped fBm
/// shader (shaders/hero.frag), drifting slowly and leaning toward the cursor.
/// The glass panels on top blur it, which is what makes them read as glass.
class LiquidBackground extends StatefulWidget {
  const LiquidBackground({super.key, required this.child});

  final Widget child;

  @override
  State<LiquidBackground> createState() => _LiquidBackgroundState();
}

class _LiquidBackgroundState extends State<LiquidBackground> with SingleTickerProviderStateMixin {
  /// Compiled once and shared — the home and settings screens both use it.
  static Future<ui.FragmentProgram>? _program;

  ui.FragmentShader? _shader;
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<double> _time = ValueNotifier(_staticTime);
  Size _size = Size.zero;
  Offset? _cursor;
  Offset? _eased;
  bool _reduceMotion = false;

  /// The frame the site renders when the visitor prefers reduced motion.
  static const double _staticTime = 12;

  @override
  void initState() {
    super.initState();
    (_program ??= ui.FragmentProgram.fromAsset('shaders/hero.frag')).then(
      (program) {
        if (!mounted) return;
        setState(() => _shader = program.fragmentShader());
        _syncTicker();
      },
      // Keep the static gradient fallback if the shader can't be loaded.
      onError: (Object _) {},
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncTicker();
  }

  void _syncTicker() {
    final shouldRun = _shader != null && !_reduceMotion;
    if (shouldRun && !_ticker.isActive) {
      _ticker.start();
    } else if (!shouldRun && _ticker.isActive) {
      _ticker.stop();
      _time.value = _staticTime;
    }
  }

  void _onTick(Duration elapsed) {
    // Same easing as the site: close 5% of the gap to the cursor each frame.
    final target = _cursor ?? _size.center(Offset.zero);
    final eased = _eased ?? target;
    _eased = eased + (target - eased) * 0.05;
    _time.value = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    return MouseRegion(
      onHover: (event) => _cursor = event.localPosition,
      onExit: (_) => _cursor = null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _size = constraints.biggest;
          return Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(
                child: shader == null
                    ? const DecoratedBox(decoration: _fallback)
                    : CustomPaint(
                        painter: _HeroPainter(
                          shader: shader,
                          time: _time,
                          cursor: () => _eased ?? _size.center(Offset.zero),
                        ),
                      ),
              ),
              widget.child,
            ],
          );
        },
      ),
    );
  }
}

/// The site's CSS backdrop behind the canvas, shown until the shader is ready.
const BoxDecoration _fallback = BoxDecoration(
  gradient: RadialGradient(
    center: Alignment(0.44, -0.76),
    radius: 1.3,
    colors: [Color(0xFF063947), Color(0xFF04141A), Color(0xFF020C0F)],
    stops: [0.0, 0.55, 1.0],
  ),
);

class _HeroPainter extends CustomPainter {
  _HeroPainter({required this.shader, required this.time, required this.cursor}) : super(repaint: time);

  final ui.FragmentShader shader;
  final ValueNotifier<double> time;
  final Offset Function() cursor;

  @override
  void paint(Canvas canvas, Size size) {
    final mouse = cursor();
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time.value)
      ..setFloat(3, mouse.dx)
      ..setFloat(4, size.height - mouse.dy);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _HeroPainter oldDelegate) => oldDelegate.shader != shader;
}
