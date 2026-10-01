import 'dart:convert';

import 'package:flutter/material.dart';

extension WidgetExtensions on Widget {
  Map<String, dynamic> toMap() {
    final type = runtimeType;
    final self = this;
    final Map<String, dynamic> map = {
      'type': type.toString(),
    };

    if (self is MultiChildRenderObjectWidget) {
      map.addAll({
        if (self.children.isNotEmpty)
          'children': self.children.map((e) => e.toMap()).toList(),
      });

      if (self is RichText) {
        final text =
            (self.text is TextSpan) ? (self.text as TextSpan).toMap() : null;

        map.addAll({
          'textAlign': self.textAlign.toString(),
          if (text != null) 'text': text,
        });
      }
    } else if (self is SingleChildRenderObjectWidget) {
      if (self is Align) {
        map.addAll({
          'alignment': self.alignment.toString(),
        });
      } else if (self is SizedBox) {
        map.addAll({
          if (self.height != null) 'height': self.height,
          if (self.width != null) 'width': self.width,
        });
      } else if (self is ConstrainedBox) {
        map.addAll({
          'constraints': self.constraints.toMap(),
          if (self.child != null) 'child': self.child?.toMap(),
        });
      }

      map.addAll({
        if (self.child != null) 'child': self.child?.toMap(),
      });
    } else if (self is Flexible) {
      map.addAll({
        'child': self.child.toMap(),
      });
    } else if (self is Table) {
      map.addAll({
        'children': self.children.map((e) => e.toMap()).toList(),
      });
    } else if (self is TableCell) {
      map.addAll({
        'child': self.child.toMap(),
      });
    } else if (self is Scrollbar) {
      map.addAll({
        'child': self.child.toMap(),
      });
    } else if (self is SingleChildScrollView) {
      map.addAll({
        if (self.child != null) 'child': self.child?.toMap(),
      });
    } else if (self is Container) {
      map.addAll({
        if (self.child != null) 'child': self.child?.toMap(),
        if (self.decoration != null) 'decoration': self.decoration!.toMap(),
      });
    } else if (self is Text) {
      map.addAll({
        'data': self.data,
      });
    } else if (self is DefaultTextStyle) {
      map.addAll({
        'child': self.child.toMap(),
      });
    } else if (self is Image) {
      map.addAll({
        'alignment': self.alignment.toString(),
      });
    }
    return map;
  }
}

extension TextSpanExtensions on TextSpan {
  Map<String, dynamic> toMap() {
    return {
      'type': runtimeType.toString(),
      if (text != null) 'text': text,
      if (style != null) 'style': style!.toMap(),
      if (children != null && children!.isNotEmpty)
        'children': children!.map((e) => (e as TextSpan).toMap()).toList(),
      if (recognizer != null) 'recognizer': recognizer.runtimeType.toString(),
    };
  }
}

extension TableRowExtensions on TableRow {
  Map<String, dynamic> toMap() {
    return {
      'type': runtimeType.toString(),
      if (children.isNotEmpty)
        'children': children.map((e) => e.toMap()).toList(),
    };
  }
}

extension DecorationExtensions on Decoration {
  Map<String, dynamic> toMap() {
    Map<String, dynamic>? borderMap;
    if (this is BoxDecoration) {
      final border = (this as BoxDecoration).border;
      if (border != null) {
        borderMap = border.toMap();
      }
    }

    return {
      'type': runtimeType.toString(),
      if (borderMap != null) 'border': borderMap,
    };
  }
}

extension BorderExtensions on BoxBorder {
  Map<String, dynamic> toMap() {
    return {
      'type': runtimeType.toString(),
      if (top.width > 0) 'top': top.toMap(),
      if (bottom.width > 0) 'bottom': bottom.toMap(),
    };
  }
}

extension BoxConstraintsExtensions on BoxConstraints {
  Map<String, dynamic> toMap() {
    return {
      'type': runtimeType.toString(),
      if (minWidth != double.infinity) 'minWidth': minWidth,
      if (minHeight != double.infinity) 'minHeight': minHeight,
      if (maxHeight != double.infinity) 'maxWidth': maxHeight,
      if (maxWidth != double.infinity) 'maxHeight': maxWidth,
    };
  }
}

extension BorderSideExtensions on BorderSide {
  Map<String, dynamic> toMap() {
    return {
      'type': runtimeType.toString(),
      'width': width,
      'color': _colorToString(color),
    };
  }
}

extension TextStyleExtensions on TextStyle {
  Map<String, dynamic> toMap() => {
        if (fontFamily != null) 'fontFamily': fontFamily,
        if (fontWeight != null) 'fontWeight': fontWeight.toString(),
        if (fontSize != null) 'fontSize': fontSize,
        if (fontStyle != null) 'fontStyle': fontStyle.toString(),
        if (color != null) 'color': _colorToString(color!),
        if (decoration != null && decoration != TextDecoration.none)
          'decoration': decoration.toString(),
        if (backgroundColor != null)
          'backgroundColor': _colorToString(backgroundColor!),
        if (fontFeatures != null)
          'fontFeatures': fontFeatures!.map((e) => e.toString()).toList(),
      };
}

extension ListExtensions on List<dynamic> {
  void addIfTrue<T>(T item, bool isTrue) {
    if (isTrue) {
      add(item);
    }
  }
}

extension MapExtensions on Map {
  String toPrettyString() => const JsonEncoder.withIndent('  ').convert(this);

  void addIfNotNull<T>(String key, T value) {
    if (value != null) {
      this[key] = value;
    }
  }
}

// Flutter's Color.toString() is intended for diagnostics and changed format
// in Flutter 3.27. Keep structural renderer snapshots stable across supported
// SDK channels by serializing the actual ARGB value instead.
String _colorToString(Color color) =>
    'Color(0x${color.toARGB32().toRadixString(16).padLeft(8, '0')})';
