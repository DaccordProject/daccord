import 'package:experience_runtime/experience_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The sole guest drawing surface. Commands describe bounded logical shapes;
/// Flutter owns layout, semantics, keyboard focus and all account interaction.
class ExperienceCanvas extends StatefulWidget {
  final List<ExperienceDrawing> drawings;
  final ValueChanged<int>? onCell;
  final int? selected;
  const ExperienceCanvas({
    super.key,
    required this.drawings,
    this.onCell,
    this.selected,
  });
  @override
  State<ExperienceCanvas> createState() => _ExperienceCanvasState();
}

class _ExperienceCanvasState extends State<ExperienceCanvas> {
  int _focused = 0;
  static const _glyphs = [
    '',
    '♙',
    '♘',
    '♗',
    '♖',
    '♕',
    '♔',
    '♟',
    '♞',
    '♝',
    '♜',
    '♛',
    '♚',
  ];
  static const _pieces = [
    'empty',
    'white pawn',
    'white knight',
    'white bishop',
    'white rook',
    'white queen',
    'white king',
    'black pawn',
    'black knight',
    'black bishop',
    'black rook',
    'black queen',
    'black king',
  ];
  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || widget.onCell == null)
      return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      _focused = (_focused + 1).clamp(0, 63);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _focused = (_focused - 1).clamp(0, 63);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _focused = (_focused + 8).clamp(0, 63);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _focused = (_focused - 8).clamp(0, 63);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space) {
      widget.onCell!(_focused);
    } else {
      return KeyEventResult.ignored;
    }
    setState(() {});
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.maxWidth.clamp(0.0, 640.0);
      return Align(
        alignment: Alignment.center,
        child: SizedBox(
          width: size,
          height: size,
          child: Focus(
            autofocus: widget.onCell != null,
            onKeyEvent: _key,
            child: ClipRect(
              child: Stack(
                children: [
                  for (final drawing in widget.drawings) _draw(drawing, size),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
  Widget _draw(ExperienceDrawing drawing, double size) {
    final v = drawing.values, cell = v[1], value = v[6];
    final chess = v[0] == 0 && cell >= 0 && cell < 64;
    final interactive = chess && widget.onCell != null;
    final selected = chess && widget.selected == cell;
    return Positioned(
      left: v[2] * size / 1024,
      top: v[3] * size / 1024,
      width: v[4] * size / 1024,
      height: v[5] * size / 1024,
      child: Semantics(
        button: interactive,
        selected: selected,
        label: chess
            ? '${String.fromCharCode(97 + cell % 8)}${cell ~/ 8 + 1}, ${value >= 0 && value < _pieces.length ? _pieces[value] : 'unknown piece'}'
            : 'Game object $cell',
        child: InkWell(
          onTap: interactive ? () => widget.onCell!(cell) : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: chess
                  ? ((cell % 8 + cell ~/ 8).isEven
                        ? const Color(0xffd9d2bd)
                        : const Color(0xff6d8260))
                  : Theme.of(context).colorScheme.primary,
              border: selected || (interactive && _focused == cell)
                  ? Border.all(color: Colors.amber, width: 3)
                  : null,
            ),
            child: Center(
              child: Text(
                chess && value >= 0 && value < _glyphs.length
                    ? _glyphs[value]
                    : '',
                style: TextStyle(fontSize: size / 11, color: Colors.black),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
