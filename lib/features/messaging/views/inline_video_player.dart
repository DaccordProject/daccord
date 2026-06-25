import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// An inline video attachment player. The underlying [Player] is created lazily
/// on first tap (so opening a channel with many videos doesn't spin up a
/// decoder per attachment); once loaded, media_kit's [Video] handles playback
/// and controls.
class InlineVideoPlayer extends StatefulWidget {
  const InlineVideoPlayer({
    super.key,
    required this.url,
    required this.filename,
    this.width,
    this.height,
  });

  final String url;
  final String filename;
  final double? width;
  final double? height;

  static const _maxWidth = 400.0;
  static const _maxHeight = 350.0;

  @override
  State<InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<InlineVideoPlayer> {
  Player? _player;
  VideoController? _controller;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  void _load() {
    final player = Player();
    setState(() {
      _player = player;
      _controller = VideoController(player);
    });
    player.open(Media(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final aspect = (widget.width != null &&
            widget.height != null &&
            widget.height! > 0)
        ? widget.width! / widget.height!
        : 16 / 9;
    final controller = _controller;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: InlineVideoPlayer._maxWidth,
          maxHeight: InlineVideoPlayer._maxHeight,
        ),
        child: AspectRatio(
          aspectRatio: aspect,
          child: controller == null
              ? GestureDetector(
                  onTap: _load,
                  child: Container(
                    color: colors.darkGray,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_circle,
                            size: 48, color: colors.dirtyWhite),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            widget.filename,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall!
                                .copyWith(color: colors.dirtyWhite),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Video(controller: controller, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
