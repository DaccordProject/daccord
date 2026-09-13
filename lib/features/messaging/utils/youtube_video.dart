/// A validated YouTube page, kept separate from the iframe player URL.
class YouTubeVideo {
  const YouTubeVideo._(this.id, this.startSeconds);
  final String id;
  final int startSeconds;

  static const _pageHosts = {
    'youtube.com', 'www.youtube.com', 'm.youtube.com', 'music.youtube.com',
  };
  static const _playerHosts = {
    'youtube-nocookie.com', 'www.youtube-nocookie.com',
  };

  static YouTubeVideo? parse(String? source) {
    if (source == null || source.contains(RegExp(r'[\s\\]'))) return null;
    try {
      final uri = Uri.tryParse(source);
      if (uri == null || !{'https', 'http'}.contains(uri.scheme) ||
          uri.userInfo.isNotEmpty ||
          (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80))) {
        return null;
      }
      final host = uri.host.toLowerCase();
      final segments = uri.pathSegments;
      final query = uri.queryParametersAll;
      // Avoid ambiguous duplicate identifiers/timestamps. Only validated ID
      // and time survive normalization; playlists, redirects and player
      // parameters supplied by message metadata never reach the iframe.
      if (['v', 'start', 't'].any((key) => (query[key]?.length ?? 0) > 1)) return null;
      String? id;
      if (host == 'youtu.be' && segments.length == 1) {
        id = segments.single;
      } else if (_pageHosts.contains(host) || _playerHosts.contains(host)) {
        if (uri.path == '/watch' && _pageHosts.contains(host)) {
          id = uri.queryParameters['v'];
        } else if (segments.length == 2 &&
            (segments.first == 'embed' ||
                (_pageHosts.contains(host) && {'shorts', 'live'}.contains(segments.first)))) {
          id = segments.last;
        }
      }
      if (id == null || !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) return null;
      final time = uri.queryParameters['start'] ?? uri.queryParameters['t'] ??
          (uri.fragment.startsWith('t=') ? uri.fragment.substring(2) : '');
      final seconds = _timestamp(time);
      return YouTubeVideo._(id, seconds);
    } on FormatException {
      // Malformed escapes in untrusted query/path data can throw during decode.
      return null;
    }
  }

  static int _timestamp(String value) {
    // Bound parsing before integer arithmetic (including on JavaScript targets).
    if (value.length > 20) return 0;
    if (RegExp(r'^\d+$').hasMatch(value)) {
      return (int.tryParse(value) ?? 0).clamp(0, 2147483647);
    }
    final units = RegExp(r'^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$').firstMatch(value);
    if (units == null || value.isEmpty) return 0;
    int unit(int index) => (int.tryParse(units[index] ?? '') ?? 0).clamp(0, 2147483647);
    final seconds = unit(1) * 3600 + unit(2) * 60 + unit(3);
    return seconds.clamp(0, 2147483647);
  }

  String get canonicalUrl => Uri.https('www.youtube.com', '/watch', {
    'v': id, if (startSeconds > 0) 't': '${startSeconds}s',
  }).toString();

  String playerUrl(String origin) {
    final page = Uri.tryParse(origin);
    if (page == null || !{'http', 'https'}.contains(page.scheme) ||
        page.host.isEmpty || page.userInfo.isNotEmpty) {
      throw ArgumentError.value(origin, 'origin', 'An HTTP(S) page origin is required');
    }
    return Uri.https('www.youtube-nocookie.com', '/embed/$id', {
      'autoplay': '1', 'playsinline': '1', 'enablejsapi': '1',
      'origin': page.origin,
      if (startSeconds > 0) 'start': '$startSeconds',
    }).toString();
  }
}

/// Native decoders only receive direct media URLs, never an HTML watch page.
bool isDirectEmbedVideo(String? source) {
  final uri = Uri.tryParse(source ?? '');
  return uri != null && {'https', 'http'}.contains(uri.scheme) &&
      uri.host.isNotEmpty && uri.userInfo.isEmpty &&
      RegExp(r'\.(mp4|m4v|mov|webm|mkv|ogv|m3u8)$', caseSensitive: false).hasMatch(uri.path);
}

/// Official IFrame API error codes, with a useful external-playback fallback.
String youtubePlaybackError(int code) => switch (code) {
  100 => 'This video is unavailable or private. Try opening it in YouTube.',
  101 || 150 => 'The video owner does not allow embedded playback. Open it in YouTube.',
  153 => 'YouTube could not verify this player. Open the video in YouTube.',
  _ => 'YouTube playback is unavailable. Try opening the video in YouTube.',
};
