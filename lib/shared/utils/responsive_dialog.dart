import 'package:flutter/widgets.dart';

/// Responsive constraints for cog-wheel / settings dialogs.
///
/// On a narrow (mobile) viewport the dialog is near full-width (a single
/// column); on a wider window it grows up to [maxWidth] (the dialog's preferred
/// desktop width) but never spills past the viewport. [maxHeight] caps the
/// height (default 90% of the viewport), also clamped to fit. This replaces the
/// fixed `BoxConstraints(maxWidth: …)` the dialogs used to hardcode, which left
/// complex forms cramped in a mobile-narrow column on desktop.
BoxConstraints dialogConstraints(
  BuildContext context, {
  required double maxWidth,
  double? maxHeight,
}) {
  final size = MediaQuery.of(context).size;
  final width = size.width < 600
      ? size.width - 24
      : maxWidth.clamp(320.0, size.width - 48);
  final height = (maxHeight ?? size.height * 0.9).clamp(
    0.0,
    size.height * 0.92,
  );
  return BoxConstraints(maxWidth: width, maxHeight: height);
}
