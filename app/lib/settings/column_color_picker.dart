import 'package:flutter/material.dart';

/// 无极颜色选择对话框，返回 [Color.toARGB32]；选「默认」返回 null。
Future<int?> showColumnColorPicker({
  required BuildContext context,
  int? currentColorValue,
  String title = '选择颜色',
  bool allowDefault = true,
}) {
  return showDialog<int?>(
    context: context,
    builder: (ctx) => _ColorPickerDialog(
      title: title,
      initialColorValue: currentColorValue,
      allowDefault: allowDefault,
    ),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({
    required this.title,
    required this.initialColorValue,
    required this.allowDefault,
  });

  final String title;
  final int? initialColorValue;
  final bool allowDefault;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv;
  bool _useDefault = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialColorValue != null) {
      _hsv = HSVColor.fromColor(Color(widget.initialColorValue!));
      _useDefault = false;
    } else {
      _hsv = const HSVColor.fromAHSV(1, 220, 0.65, 0.85);
      _useDefault = widget.allowDefault;
    }
  }

  Color get _color => _hsv.toColor();

  void _pickSv(Offset local, Size size) {
    final s = (local.dx / size.width).clamp(0.0, 1.0);
    final v = (1 - local.dy / size.height).clamp(0.0, 1.0);
    setState(() {
      _useDefault = false;
      _hsv = _hsv.withSaturation(s).withValue(v);
    });
  }

  void _pickHue(double ratio) {
    setState(() {
      _useDefault = false;
      _hsv = _hsv.withHue(ratio * 360);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.allowDefault)
              Align(
                alignment: Alignment.centerLeft,
                child: FilterChip(
                  label: const Text('默认'),
                  selected: _useDefault,
                  onSelected: (v) => setState(() => _useDefault = v),
                ),
              ),
            if (widget.allowDefault) const SizedBox(height: 8),
            Opacity(
              opacity: _useDefault ? 0.4 : 1,
              child: IgnorePointer(
                ignoring: _useDefault,
                child: Column(
                  children: [
                    _SvPicker(
                      hue: _hsv.hue,
                      saturation: _hsv.saturation,
                      value: _hsv.value,
                      onPick: _pickSv,
                    ),
                    const SizedBox(height: 12),
                    _HueSlider(hue: _hsv.hue, onChanged: _pickHue),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _color,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '#${_color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, widget.initialColorValue),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context, _useDefault ? null : _color.toARGB32());
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class _SvPicker extends StatelessWidget {
  const _SvPicker({
    required this.hue,
    required this.saturation,
    required this.value,
    required this.onPick,
  });

  final double hue;
  final double saturation;
  final double value;
  final void Function(Offset local, Size size) onPick;

  @override
  Widget build(BuildContext context) {
    const height = 160.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, height);
        return GestureDetector(
          onPanDown: (d) => onPick(d.localPosition, size),
          onPanUpdate: (d) => onPick(d.localPosition, size),
          onTapDown: (d) => onPick(d.localPosition, size),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: Stack(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white,
                          HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
                        ],
                      ),
                    ),
                    child: const SizedBox.expand(),
                  ),
                  DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black],
                      ),
                    ),
                    child: const SizedBox.expand(),
                  ),
                  Positioned(
                    left: saturation * size.width - 8,
                    top: (1 - value) * size.height - 8,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 2,
                          ),
                        ],
                      ),
                    ),
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

class _HueSlider extends StatelessWidget {
  const _HueSlider({required this.hue, required this.onChanged});

  final double hue;
  final void Function(double ratio) onChanged;

  @override
  Widget build(BuildContext context) {
    const height = 24.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          onPanDown: (d) => onChanged((d.localPosition.dx / width).clamp(0, 1)),
          onPanUpdate: (d) =>
              onChanged((d.localPosition.dx / width).clamp(0, 1)),
          onTapDown: (d) => onChanged((d.localPosition.dx / width).clamp(0, 1)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: height,
              child: Stack(
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
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
                    child: SizedBox.expand(),
                  ),
                  Positioned(
                    left: (hue / 360) * width - 8,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 2),
                          ],
                        ),
                      ),
                    ),
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
