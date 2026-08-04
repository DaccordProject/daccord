import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:bonfire/shared/utils/download_attachment.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// A compact inline audio player for an audio attachment. The source is loaded
/// lazily on first play; play/pause and a seek slider are exposed.
class InlineAudioPlayer extends StatefulWidget {
  const InlineAudioPlayer({super.key, required this.url, required this.filename});

  final String url;
  final String filename;

  @override
  State<InlineAudioPlayer> createState() => _InlineAudioPlayerState();
}

class _InlineAudioPlayerState extends State<InlineAudioPlayer> {
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subs = [];
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _started = false;

  /// A download in flight. `_progress` is null while the total size is unknown
  /// (no `Content-Length`), which renders as an indeterminate spinner.
  bool _downloading = false;
  double? _progress;

  /// The last failure, shown inline under the transport row until the next
  /// attempt. Cleared on retry so a stale message can't outlive its cause.
  String? _downloadError;

  @override
  void initState() {
    super.initState();
    _subs.add(_player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    }));
    _subs.add(_player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    }));
    _subs.add(_player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    }));
    _subs.add(_player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _position = Duration.zero;
        });
      }
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
    } else if (!_started) {
      _started = true;
      await _player.play(UrlSource(widget.url));
    } else {
      await _player.resume();
    }
  }

  Future<void> _download() async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _progress = null;
      _downloadError = null;
    });

    final result = await downloadAttachment(
      widget.url,
      filename: widget.filename,
      // Throttling isn't needed here: progress arrives per HTTP chunk, and the
      // player is a small widget in an already-scrolling list.
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );

    if (!mounted) return;
    setState(() {
      _downloading = false;
      _progress = null;
      _downloadError = result.error;
    });

    switch (result.outcome) {
      case DownloadOutcome.saved:
        _confirmSaved(result);
      case DownloadOutcome.handedToBrowser:
      case DownloadOutcome.cancelled:
      case DownloadOutcome.failed:
        // Browser downloads report themselves, cancelling is the user's own
        // doing, and failures render inline via [_downloadError].
        break;
    }
  }

  /// Confirms a completed save, offering to reveal the file where the platform
  /// has a file manager to open.
  void _confirmSaved(DownloadResult result) {
    final path = result.path;
    final reveal = result.canReveal && canRevealDownloads;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          reveal ? 'Saved to ${_folderOf(path!)}' : 'Saved ${widget.filename}',
        ),
        action: reveal
            ? SnackBarAction(
                label: 'Show in folder',
                onPressed: () => revealDownloadedFile(path!),
              )
            : null,
      ),
    );
  }

  /// The containing folder's name, for a confirmation that says where the file
  /// went without spilling the user's full home path into the UI.
  String _folderOf(String path) {
    final parts = path.split(RegExp(r'[/\\]'))..removeLast();
    return parts.isEmpty || parts.last.isEmpty ? 'your downloads' : parts.last;
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final maxMs = _duration.inMilliseconds;
    final value = maxMs == 0
        ? 0.0
        : _position.inMilliseconds.clamp(0, maxMs).toDouble();
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colors.darkGray,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.audiotrack, size: 16, color: colors.dirtyWhite),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.filename,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall!
                      .copyWith(color: colors.dirtyWhite),
                ),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                iconSize: 28,
                onPressed: _toggle,
                icon: Icon(
                  _playing ? Icons.pause_circle : Icons.play_circle,
                  color: colors.primary,
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context)
                      .copyWith(trackHeight: 2, overlayShape: SliderComponentShape.noOverlay),
                  child: Slider(
                    value: value,
                    max: maxMs == 0 ? 1 : maxMs.toDouble(),
                    onChanged: maxMs == 0
                        ? null
                        : (v) => _player
                            .seek(Duration(milliseconds: v.toInt())),
                  ),
                ),
              ),
              Text(
                '${_fmt(_position)} / ${_fmt(_duration)}',
                style:
                    theme.textTheme.labelSmall!.copyWith(color: colors.gray),
              ),
              const SizedBox(width: 2),
              // Sized to match the IconButton it swaps places with, so the row
              // doesn't reflow when a download starts.
              SizedBox(
                width: 32,
                height: 32,
                child: _downloading
                    ? Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            value: _progress,
                            color: colors.primary,
                          ),
                        ),
                      )
                    : IconButton(
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        splashRadius: 16,
                        tooltip: 'Download',
                        onPressed: _download,
                        icon: Icon(
                          Icons.download_outlined,
                          color: colors.dirtyWhite,
                        ),
                      ),
              ),
              const SizedBox(width: 2),
            ],
          ),
          if (_downloadError != null)
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 8, bottom: 4),
              child: Text(
                _downloadError!,
                style: theme.textTheme.labelSmall!.copyWith(color: colors.red),
              ),
            ),
        ],
      ),
    );
  }
}
