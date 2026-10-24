import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'glass_container.dart';

/// Compact HSV picker so annotations aren't limited to the fixed swatches on
/// the toolbar. Returns the chosen colour, or null if dismissed.
class ColorPickerPopup extends StatefulWidget {
  const ColorPickerPopup({super.key, required this.initial});

  final Color initial;

  static Future<Color?> show(BuildContext context, Color initial) {
    return showDialog<Color>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => ColorPickerPopup(initial: initial),
    );
  }

  @override
  State<ColorPickerPopup> createState() => _ColorPickerPopupState();
}

class _ColorPickerPopupState extends State<ColorPickerPopup> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  static const double _panelWidth = 248;
  static const double _squareHeight = 150;
  static const double _stripHeight = 18;

  Color get _color => _hsv.toColor();

  void _pickSaturationValue(Offset local, Size size) {
    setState(() {
      _hsv = _hsv
          .withSaturation((local.dx / size.width).clamp(0.0, 1.0))
          .withValue(1 - (local.dy / size.height).clamp(0.0, 1.0));
    });
  }

  void _pickHue(Offset local) {
    setState(() {
      _hsv = _hsv.withHue(((local.dx / _panelWidth).clamp(0.0, 1.0)) * 360);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    // showDialog doesn't insert a Material ancestor, and without one Flutter
    // falls back to its debug text style (yellow underlines) and InkWell
    // splashes have nothing to paint on.
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: GlassContainer(
          padding: const EdgeInsets.all(16),
          borderRadius: 22,
          child: SizedBox(
            width: _panelWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pick a colour',
                  style: TextStyle(
                      color: palette.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                _SaturationValueSquare(
                  hue: _hsv.hue,
                  saturation: _hsv.saturation,
                  value: _hsv.value,
                  height: _squareHeight,
                  onChanged: _pickSaturationValue,
                ),
                const SizedBox(height: 12),
                _HueStrip(
                  hue: _hsv.hue,
                  height: _stripHeight,
                  width: _panelWidth,
                  onChanged: _pickHue,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: _color,
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.ghostBorder, width: 1.5),
                        boxShadow: glow(_color, alpha: 0.5, blur: 14),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '#${(_color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                      style: TextStyle(
                          color: palette.textSoft,
                          fontSize: 12,
                          letterSpacing: 1),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 4),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(_color),
                      child: const Text('Use'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SaturationValueSquare extends StatelessWidget {
  const _SaturationValueSquare({
    required this.hue,
    required this.saturation,
    required this.value,
    required this.height,
    required this.onChanged,
  });

  final double hue;
  final double saturation;
  final double value;
  final double height;
  final void Function(Offset local, Size size) onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, height);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => onChanged(d.localPosition, size),
          onPanUpdate: (d) => onChanged(d.localPosition, size),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: size.width,
              height: height,
              child: Stack(
                children: [
                  // Fully saturated hue, then white across and black down —
                  // the standard saturation/value square.
                  Positioned.fill(
                    child: ColoredBox(
                        color: HSVColor.fromAHSV(1, hue, 1, 1).toColor()),
                  ),
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.white, Color(0x00FFFFFF)],
                        ),
                      ),
                    ),
                  ),
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00000000), Colors.black],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: saturation * size.width - 8,
                    top: (1 - value) * height - 8,
                    child: const _Knob(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HueStrip extends StatelessWidget {
  const _HueStrip({
    required this.hue,
    required this.height,
    required this.width,
    required this.onChanged,
  });

  final double hue;
  final double height;
  final double width;
  final ValueChanged<Offset> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanDown: (d) => onChanged(d.localPosition),
      onPanUpdate: (d) => onChanged(d.localPosition),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(height / 2),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFFF0000),
                      Color(0xFFFFFF00),
                      Color(0xFF00FF00),
                      Color(0xFF00FFFF),
                      Color(0xFF0000FF),
                      Color(0xFFFF00FF),
                      Color(0xFFFF0000),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: (hue / 360) * width - 8,
              top: height / 2 - 8,
              child: const _Knob(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Knob extends StatelessWidget {
  const _Knob();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
      ),
    );
  }
}
