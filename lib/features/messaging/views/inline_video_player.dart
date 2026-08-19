import 'package:bonfire/theme/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player/video_player.dart' as vp;

/// An inline video attachment player. Playback starts lazily on first tap (so
/// opening a channel with many videos doesn't spin up a decoder per
/// attachment).
///
/// The decoder differs by platform: everywhere except iOS this is media_kit's
/// [Player] + [Video], which brings its own controls. iOS has no libmpv bundled
/// — media_kit's iOS native libs reference fork/execve and the deprecated
/// OpenGL ES stack, which App Review rejects under guideline 2.5.1, so they're
/// excluded in pubspec.yaml — and plays through package:video_player's
/// AVFoundation backend with the small control overlay below.
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

  /// Containers AVFoundation can demux. libmpv plays everything in
  /// `attachment_types.dart`'s video list; AVFoundation covers only the MPEG-4
  /// / QuickTime family plus HLS, so on iOS the rest are shown as a dead poster
  /// rather than a player that would fail on the first frame.
  static const _avFoundationExtensions = {'mp4', 'm4v', 'mov', 'm3u8'};

  /// Whether this platform can decode what [url] points at. Embeds pass a title
  /// as [filename], so the URL's own path is the reliable signal; the filename
  /// is only consulted when the URL carries no extension.
  bool get _playableHere {
    if (!_isIOS) return true;
    final path = Uri.tryParse(url)?.path ?? '';
    return _avFoundationExtensions.contains(_extensionOf(path)) ||
        (!path.contains('.') &&
            _avFoundationExtensions.contains(_extensionOf(filename)));
  }

  static bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static String? _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? null : name.substring(dot + 1).toLowerCase();
  }

  @override
  State<InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<InlineVideoPlayer> {
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    final aspect = (widget.width != null &&
            widget.height != null &&
            widget.height! > 0)
        ? widget.width! / widget.height!
        : 16 / 9;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: InlineVideoPlayer._maxWidth,
          maxHeight: InlineVideoPlayer._maxHeight,
        ),
        child: AspectRatio(
          aspectRatio: aspect,
          child: !widget._playableHere
              ? _VideoPoster(
                  filename: widget.filename,
                  icon: Icons.videocam_off,
                )
              : !_loaded
                  ? GestureDetector(
                      onTap: () => setState(() => _loaded = true),
                      child: _VideoPoster(filename: widget.filename),
                    )
                  : InlineVideoPlayer._isIOS
                      ? _AvFoundationVideo(url: widget.url)
                      : _MediaKitVideo(url: widget.url),
        ),
      ),
    );
  }
}

/// The tap-to-play placeholder shown before a decoder is created — or, with
/// [icon] overridden, the dead-end shown for a container this platform can't
/// decode.
class _VideoPoster extends StatelessWidget {
  const _VideoPoster({required this.filename, this.icon = Icons.play_circle});

  final String filename;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      color: colors.darkGray,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: colors.dirtyWhite),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              filename,
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
    );
  }
}

/// libmpv-backed playback — every platform except iOS.
class _MediaKitVideo extends StatefulWidget {
  const _MediaKitVideo({required this.url});

  final String url;

  @override
  State<_MediaKitVideo> createState() => _MediaKitVideoState();
}

class _MediaKitVideoState extends State<_MediaKitVideo> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  @override
  void initState() {
    super.initState();
    _player.open(Media(widget.url));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Video(controller: _controller, fit: BoxFit.contain);
}

/// AVFoundation-backed playback — iOS only. package:video_player ships no
/// controls, so this adds the minimum: tap to toggle play/pause, a play glyph
/// while paused, and a scrub bar along the bottom.
class _AvFoundationVideo extends StatefulWidget {
  const _AvFoundationVideo({required this.url});

  final String url;

  @override
  State<_AvFoundationVideo> createState() => _AvFoundationVideoState();
}

class _AvFoundationVideoState extends State<_AvFoundationVideo> {
  late final vp.VideoPlayerController _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _controller = vp.VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _controller.play();
      }).catchError((Object e) {
        if (!mounted) return;
        setState(() => _error = e);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    if (_error != null) {
      return Container(
        color: colors.darkGray,
        alignment: Alignment.center,
        child: Icon(Icons.videocam_off, size: 40, color: colors.dirtyWhite),
      );
    }
    if (!_controller.value.isInitialized) {
      return Container(
        color: colors.darkGray,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return GestureDetector(
      onTap: () => setState(() {
        if (_controller.value.isPlaying) {
          _controller.pause();
        } else {
          _controller.play();
        }
      }),
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: vp.VideoPlayer(_controller),
              ),
            ),
            if (!_controller.value.isPlaying)
              Icon(Icons.play_circle, size: 48, color: colors.dirtyWhite),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: vp.VideoProgressIndicator(_controller, allowScrubbing: true),
            ),
          ],
        ),
      ),
    );
  }
}
