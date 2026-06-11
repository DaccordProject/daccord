import 'dart:typed_data';

import 'package:bonfire/theme/theme.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

/// Modal that lets the user pan (x/y) and zoom an image inside a fixed-aspect
/// frame, then returns the cropped bytes (PNG). Mirrors the reposition+zoom
/// flow Discord uses for server icons/banners and user avatars.
///
/// The crop rect is fixed at [aspectRatio]; the user moves the image behind it.
/// [circular] only changes the mask shape — the output is always rectangular
/// (square when [aspectRatio] is 1), since icons/avatars are rounded at display
/// time. Returns null if the user cancels.
Future<Uint8List?> showImageCropDialog(
  BuildContext context, {
  required Uint8List imageBytes,
  required double aspectRatio,
  bool circular = false,
  String title = 'Edit image',
}) {
  return showDialog<Uint8List?>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ImageCropDialog(
      imageBytes: imageBytes,
      aspectRatio: aspectRatio,
      circular: circular,
      title: title,
    ),
  );
}

class _ImageCropDialog extends StatefulWidget {
  const _ImageCropDialog({
    required this.imageBytes,
    required this.aspectRatio,
    required this.circular,
    required this.title,
  });

  final Uint8List imageBytes;
  final double aspectRatio;
  final bool circular;
  final String title;

  @override
  State<_ImageCropDialog> createState() => _ImageCropDialogState();
}

class _ImageCropDialogState extends State<_ImageCropDialog> {
  final _controller = CropController();
  bool _busy = false;

  void _apply() {
    if (_busy) return;
    setState(() => _busy = true);
    _controller.crop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Dialog(
      backgroundColor: colors.foreground,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 580),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Crop(
                    image: widget.imageBytes,
                    controller: _controller,
                    aspectRatio: widget.aspectRatio,
                    withCircleUi: widget.circular,
                    interactive: true,
                    fixCropRect: true,
                    initialRectBuilder: InitialRectBuilder.withSizeAndRatio(
                      size: 1,
                      aspectRatio: widget.aspectRatio,
                    ),
                    baseColor: colors.background,
                    maskColor: Colors.black.withValues(alpha: 0.55),
                    radius: widget.circular ? 0 : 6,
                    cornerDotBuilder: (_, _) => const SizedBox.shrink(),
                    onCropped: (result) {
                      if (!mounted) return;
                      switch (result) {
                        case CropSuccess(:final croppedImage):
                          Navigator.of(context).pop(croppedImage);
                        case CropFailure():
                          setState(() => _busy = false);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Drag to reposition · scroll or pinch to zoom',
                style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _apply,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
