import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// alienwavegroup.com's animated hero background: the same domain-warped fBm
/// shader (shaders/hero.frag), drifting slowly and leaning toward the cursor.
/// The glass panels on top blur it, which is what makes them read as glass.
class LiquidBackground extends StatefulWidget {
  const LiquidBackground({super.key, required this.child});

  final Widget child;

  @override
  State<LiquidBackground> createState() => _LiquidBackgroundState();
}

class _LiquidBackgroundState extends State<LiquidBackground> {
  /// Compiled once and shared — the home and settings screens both use it.
  static Future<ui.FragmentProgram>? _program;

  /// A timer rather than a Ticker: a Ticker produces a frame on every vsync,
  /// and each frame re-blurs every glass panel — on a 144 Hz display that kept
  /// the open window at several percent CPU. The drift is slow enough that
  /// 30 fps looks the same.
  static const Duration _frameInterval = Duration(milliseconds: 33);

  ui.FragmentShader? _shader;
  Timer? _timer;
  final Stopwatch _clock = Stopwatch();
  final ValueNotifier<double> _time = ValueNotifier(_staticTime);
  Size _size = Size.zero;
  Offset? _cursor;
  Offset? _eased;
  bool _reduceMotion = false;

  /// False while the window is hidden (the app wraps its screens in a
  /// disabled [TickerMode] then), so nothing renders in the tray.
  bool _tickersEnabled = true;

  /// The frame the site renders when the visitor prefers reduced motion.
  static const double _staticTime = 12;

  @override
  void initState() {
    super.initState();
    // The shader redraws every frame of the timer below. On macOS that's
    // routed through ANGLE/Metal and costs noticeably more CPU than on
    // Windows for the same 30 fps — enough that it showed up as "load" on
    // an otherwise idle screenshot tool. Mac just gets the static gradient.
    if (Platform.isMacOS) return;
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
    _tickersEnabled = TickerMode.valuesOf(context).enabled;
    _syncTicker();
  }

  void _syncTicker() {
    final shouldRun = _shader != null && !_reduceMotion && _tickersEnabled;
    if (shouldRun && _timer == null) {
      _clock.start();
      _timer = Timer.periodic(_frameInterval, (_) => _onTick());
    } else if (!shouldRun && _timer != null) {
      _timer!.cancel();
      _timer = null;
      _clock.stop();
      if (_reduceMotion) _time.value = _staticTime;
    }
  }

  void _onTick() {
    // Same easing as the site: close a share of the gap to the cursor each
    // frame (5% at 60 fps, so twice that at this rate).
    final target = _cursor ?? _size.center(Offset.zero);
    final eased = _eased ?? target;
    _eased = eased + (target - eased) * 0.1;
    _time.value = _clock.elapsedMicroseconds / Duration.microsecondsPerSecond;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _time.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    final light = AlienPalette.of(context).isLight;
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
                    ? DecoratedBox(decoration: light ? _fallbackLight : _fallbackDark)
                    : CustomPaint(
                        painter: _HeroPainter(
                          shader: shader,
                          time: _time,
                          light: light,
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
const BoxDecoration _fallbackDark = BoxDecoration(
  gradient: RadialGradient(
    center: Alignment(0.44, -0.76),
    radius: 1.3,
    colors: [Color(0xFF063947), Color(0xFF04141A), Color(0xFF020C0F)],
    stops: [0.0, 0.55, 1.0],
  ),
);

const BoxDecoration _fallbackLight = BoxDecoration(
  gradient: RadialGradient(
    center: Alignment(0.44, -0.76),
    radius: 1.3,
    colors: [Color(0xFFC2E1F6), Color(0xFFEEF6FC), Color(0xFFDDEEFA)],
    stops: [0.0, 0.55, 1.0],
  ),
);

class _HeroPainter extends CustomPainter {
  _HeroPainter({
    required this.shader,
    required this.time,
    required this.light,
    required this.cursor,
  }) : super(repaint: time);

  final ui.FragmentShader shader;
  final ValueNotifier<double> time;
  final bool light;
  final Offset Function() cursor;

  @override
  void paint(Canvas canvas, Size size) {
    final mouse = cursor();
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time.value)
      ..setFloat(3, mouse.dx)
      ..setFloat(4, size.height - mouse.dy)
      ..setFloat(5, light ? 1 : 0);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _HeroPainter oldDelegate) =>
      oldDelegate.shader != shader || oldDelegate.light != light;
}
