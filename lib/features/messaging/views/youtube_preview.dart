import 'package:bonfire/features/messaging/utils/youtube_video.dart';
import 'package:bonfire/features/messaging/views/message_media_gate.dart';
import 'package:bonfire/features/messaging/views/youtube_player.dart';
import 'package:bonfire/shared/utils/external_url.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

typedef YouTubePlayerBuilder = Widget Function(
  YouTubeVideo video, VoidCallback onStopped, ValueChanged<String> onError,
);

class YouTubePreview extends StatefulWidget {
  const YouTubePreview({super.key, required this.video, this.poster, this.cdnUrl,
    this.playerBuilder,
  });
  final YouTubeVideo video;
  final String? poster;
  final String? cdnUrl;
  @visibleForTesting
  final YouTubePlayerBuilder? playerBuilder;
  @override
  State<YouTubePreview> createState() => _YouTubePreviewState();
}

class _YouTubePreviewState extends State<YouTubePreview> with WidgetsBindingObserver {
  bool _playing = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  @override
  void didUpdateWidget(YouTubePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.canonicalUrl != widget.video.canonicalUrl || oldWidget.cdnUrl != widget.cdnUrl) {
      _playing = false;
      _error = null;
    }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _stop();
  }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.of(context)) _playing = false;
  }
  void _stop() {
    if (mounted && _playing) setState(() => _playing = false);
  }
  void _failed(String message) {
    if (!mounted) return;
    setState(() {
      _playing = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    // YouTube requires at least 200x200; retain 16:9 and use external playback
    // when the message column is too narrow to satisfy both dimensions.
    final canPlay = (supportsYouTubePlayer || widget.playerBuilder != null) && constraints.maxWidth >= 356;
    // A resize cannot silently resume playback when enough width returns.
    if (!canPlay) _playing = false;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('YouTube'),
      AspectRatio(aspectRatio: 16 / 9, child: _playing
          ? widget.playerBuilder?.call(widget.video, _stop, _failed) ??
              YouTubePlayer(key: ValueKey(widget.video.canonicalUrl), video: widget.video, onStopped: _stop, onError: _failed)
          : ColoredBox(color: Colors.black12, child: widget.poster == null
              ? const Center(child: Icon(Icons.smart_display, size: 48))
              : MessageMediaGate(
                  source: widget.poster, trustedBaseUrl: widget.cdnUrl,
                  blockedPlaceholder: const Center(child: Icon(Icons.smart_display, size: 48)),
                  builder: (_, url) => CachedNetworkImage(imageUrl: url,
                    fit: BoxFit.contain,
                    errorWidget: (_, _, _) => const Center(child: Icon(Icons.smart_display, size: 48))),
                ))),
      if (_error != null) Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(_error!, key: const ValueKey('youtube-playback-error')),
      ),
      if (canPlay && !_playing) const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text('Playing loads content from YouTube and shares your connection with Google.'),
      ),
      Wrap(spacing: 8, children: [
        if (canPlay) TextButton.icon(
          key: const ValueKey('youtube-play'),
          onPressed: _playing ? _stop : () => setState(() {
            _error = null;
            _playing = true;
          }),
          icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
          label: Text(_playing ? 'Stop playback' : 'Play · load from YouTube'),
        ),
        TextButton.icon(
          onPressed: () => openExternalUrl(context, widget.video.canonicalUrl),
          icon: const Icon(Icons.open_in_new), label: const Text('Open in YouTube'),
        ),
      ]),
    ]);
  });
}
