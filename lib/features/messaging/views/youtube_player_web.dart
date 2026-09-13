import 'dart:async';
import 'dart:js_interop';

import 'package:bonfire/features/messaging/utils/youtube_video.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

const supportsYouTubePlayer = true;

@JS('YT')
external _YouTubeNamespace? get _youtube;

extension type _YouTubeNamespace._(JSObject _) implements JSObject {
  @JS('Player')
  external JSFunction? get playerConstructor;
}

@JS('YT.Player')
extension type _YouTubeApiPlayer._(JSObject _) implements JSObject {
  external factory _YouTubeApiPlayer(
    web.HTMLIFrameElement frame,
    JSObject options,
  );
  external void destroy();
}

extension type _YouTubeEvent._(JSObject _) implements JSObject {
  external int get data;
}

@JS('onYouTubeIframeAPIReady')
external JSFunction? get _onApiReady;
@JS('onYouTubeIframeAPIReady')
external set _onApiReady(JSFunction? value);

Future<void>? _apiLoading;

/// The only executable third-party script is YouTube's official IFrame API.
/// This function is reached only after consent and after the view is attached.
Future<void> _loadYouTubeApi() {
  if (_youtube?.playerConstructor != null) return Future.value();
  return _apiLoading ??= _insertApiScript();
}

Future<void> _insertApiScript() async {
  final ready = Completer<void>();
  final previousReady = _onApiReady;
  final script = web.HTMLScriptElement()
    ..src = 'https://www.youtube.com/iframe_api'
    ..referrerPolicy = 'strict-origin-when-cross-origin';
  final callback = (() {
    if (!ready.isCompleted) ready.complete();
    previousReady?.callAsFunction();
  }).toJS;
  _onApiReady = callback;
  final error = ((web.Event _) {
    if (!ready.isCompleted)
      ready.completeError(StateError('YouTube API could not load'));
  }).toJS;
  script.addEventListener('error', error);
  web.document.head!.appendChild(script);
  try {
    await ready.future.timeout(const Duration(seconds: 20));
    if (_youtube?.playerConstructor == null)
      throw StateError('YouTube API unavailable');
  } catch (_) {
    _apiLoading = null;
    rethrow;
  } finally {
    script.removeEventListener('error', error);
    script.remove();
    if (_onApiReady == callback) _onApiReady = previousReady;
  }
}

/// Only validated YouTube IDs reach this sandboxed iframe. Using the official
/// API gives us video-owner/private-video errors that iframe.onload/onerror
/// cannot detect. See developers.google.com/youtube/iframe_api_reference.
class YouTubePlayer extends StatefulWidget {
  const YouTubePlayer({
    super.key,
    required this.video,
    required this.onStopped,
    required this.onError,
  });
  final YouTubeVideo video;
  final VoidCallback onStopped;
  final ValueChanged<String> onError;
  @override
  State<YouTubePlayer> createState() => _YouTubePlayerState();
}

class _YouTubePlayerState extends State<YouTubePlayer> {
  web.HTMLIFrameElement? _frame;
  web.IntersectionObserver? _observer;
  _YouTubeApiPlayer? _player;
  Timer? _readyTimeout;
  bool _starting = false;
  bool _closed = false;
  bool _wasVisible = false;
  late final JSFunction _visibilityListener = ((web.Event _) {
    if (web.document.hidden) _stop();
  }).toJS;

  @override
  void initState() {
    super.initState();
    web.document.addEventListener('visibilitychange', _visibilityListener);
  }

  void _release() {
    _closed = true;
    _readyTimeout?.cancel();
    _observer?.disconnect();
    web.document.removeEventListener('visibilitychange', _visibilityListener);
    // Blank first even if the provider API is unavailable or destroy throws.
    _frame?.src = 'about:blank';
    try {
      _player?.destroy();
    } catch (_) {
      // The iframe is already inert; DOM removal below completes cleanup.
    }
    _player = null;
    _frame?.remove();
    _frame = null;
  }

  void _stop({String? error}) {
    if (_closed) return;
    _release();
    if (!mounted) return;
    // DOM/JS callbacks can run during platform-view creation. Schedule the
    // Flutter parent update after the current build instead of inside it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (error == null) {
        widget.onStopped();
      } else {
        widget.onError(error);
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _start() async {
    if (_starting || _closed) return;
    _starting = true;
    try {
      await _loadYouTubeApi();
      final frame = _frame;
      if (!mounted || _closed || frame == null) return;
      if (web.document.hidden || !frame.isConnected) {
        _stop();
        return;
      }
      frame.src = widget.video.playerUrl(web.window.location.origin);
      _readyTimeout = Timer(const Duration(seconds: 20), () {
        _stop(error: 'YouTube did not load. Try opening the video in YouTube.');
      });
      _player = _YouTubeApiPlayer(
        frame,
        {
              'events': {
                'onReady': ((JSObject _) {
                  _readyTimeout?.cancel();
                }).toJS,
                'onError': ((_YouTubeEvent event) {
                  _stop(error: youtubePlaybackError(event.data));
                }).toJS,
              },
            }.jsify()!
            as JSObject,
      );
    } catch (_) {
      _stop(error: 'YouTube could not load. Try opening the video in YouTube.');
    }
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
    tagName: 'iframe',
    onElementCreated: (element) {
      final frame = element as web.HTMLIFrameElement;
      if (_closed) {
        frame.remove();
        return;
      }
      _frame = frame;
      frame
        ..title = 'YouTube video player'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.border = '0'
        ..referrerPolicy = 'strict-origin-when-cross-origin'
        ..allow = 'autoplay; encrypted-media; fullscreen; picture-in-picture'
        ..allowFullscreen = true;
      frame.setAttribute(
        'sandbox',
        'allow-scripts allow-same-origin allow-presentation',
      );
      frame.addEventListener(
        'error',
        ((web.Event _) {
          _stop(
            error: 'YouTube could not load. Try opening the video in YouTube.',
          );
        }).toJS,
      );
      _observer = web.IntersectionObserver(
        ((
              JSArray<web.IntersectionObserverEntry> entries,
              web.IntersectionObserver observer,
            ) {
              for (final entry in entries.toDart) {
                if (entry.isIntersecting && entry.intersectionRatio > 0) {
                  _wasVisible = true;
                  unawaited(_start());
                } else if (_wasVisible || frame.isConnected) {
                  _stop();
                }
              }
            })
            .toJS,
      );
      // Observing the frame also waits for its DOM attachment before YT.Player
      // is constructed, as required by HtmlElementView.fromTagName.
      _observer!.observe(frame);
    },
  );
}
