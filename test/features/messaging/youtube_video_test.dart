import 'package:bonfire/features/messaging/utils/youtube_video.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const id = 'dQw4w9WgXcQ';
  group('YouTube URL normalization', () {
    for (final source in [
      'https://youtube.com/watch?v=$id',
      'http://www.youtube.com/watch?v=$id',
      'https://m.youtube.com/watch?v=$id',
      'https://music.youtube.com/watch?v=$id',
      'https://youtu.be/$id',
      'https://www.youtube.com/shorts/$id',
      'https://www.youtube.com/live/$id',
      'https://www.youtube.com/embed/$id',
      'https://www.youtube-nocookie.com/embed/$id',
      'https://youtube-nocookie.com/embed/$id',
    ]) {
      test('normalizes $source', () {
        final video = YouTubeVideo.parse(source)!;
        expect(video.id, id);
        expect(video.canonicalUrl, 'https://www.youtube.com/watch?v=$id');
      });
    }

    test('normalizes timestamps and strips all untrusted player options', () {
      final video = YouTubeVideo.parse(
        'https://youtu.be/$id?t=1h2m3s&origin=https://evil.test&autoplay=1&list=playlist',
      )!;
      expect(video.startSeconds, 3723);
      final player = Uri.parse(
        video.playerUrl('https://chat.example:8443/path'),
      );
      expect(player.host, 'www.youtube-nocookie.com');
      expect(player.path, '/embed/$id');
      expect(player.queryParameters, {
        'autoplay': '1',
        'playsinline': '1',
        'enablejsapi': '1',
        'origin': 'https://chat.example:8443',
        'start': '3723',
      });
      expect(video.canonicalUrl, 'https://www.youtube.com/watch?v=$id&t=3723s');
    });

    for (final entry in {
      '?t=90': 90,
      '?start=20&t=30': 20,
      '#t=1m5s': 65,
      '?t=-1': 0,
      '?t=NaN': 0,
      '?t=9000000000': 2147483647,
      '?t=999999999999999999h': 2147483647,
    }.entries) {
      test('timestamp ${entry.key}', () {
        expect(
          YouTubeVideo.parse('https://youtu.be/$id${entry.key}')!.startSeconds,
          entry.value,
        );
      });
    }

    for (final source in [
      null,
      '',
      'javascript:alert(1)',
      'file:///tmp/video',
      '//youtube.com/watch?v=$id',
      'https://youtube.com.evil.test/watch?v=$id',
      'https://evil.youtube.com/watch?v=$id',
      'https://youtube.com@evil.test/watch?v=$id',
      'https://user@youtube.com/watch?v=$id',
      'https://youtu.be:8443/$id',
      'https://youtube.com/watch?v=short',
      'https://youtube.com/watch?v=$id&v=aaaaaaaaaaa',
      'https://youtu.be/$id?t=1&t=2',
      'https://youtu.be/$id/extra',
      'https://youtube.com/embed/%2F$id',
      'https://youtube.com/embed/%E0%A4%A',
      'https://youtube.com/watch?v=%FF',
      'https://youtube.com/watch?v=$id%0A',
      'https://youtube.com/redirect?q=https://youtu.be/$id',
      'https://youtube-nocookie.com/watch?v=$id',
      'https://youtube.com/playlist?list=$id',
      'https://youtu.be/$id\\evil',
      ' https://youtu.be/$id',
    ]) {
      test('rejects malicious or ambiguous source $source', () {
        expect(YouTubeVideo.parse(source), isNull);
      });
    }

    test('player rejects opaque/local origins', () {
      final video = YouTubeVideo.parse('https://youtu.be/$id')!;
      for (final origin in [
        'null',
        'file:///tmp/page',
        'javascript:alert(1)',
        'https://user@chat.test',
      ]) {
        expect(() => video.playerUrl(origin), throwsArgumentError);
      }
    });
  });

  test('HTML provider URLs never reach a native decoder', () {
    for (final url in [
      'https://youtube.com/watch?v=$id',
      'https://youtu.be/$id',
      'https://youtube.com/embed/$id',
      'https://video.test/player',
      'file:///video.mp4',
      'https://user@video.test/video.mp4',
    ]) {
      expect(isDirectEmbedVideo(url), isFalse, reason: url);
    }
    expect(
      isDirectEmbedVideo('https://cdn.test/clip.MP4?signature=abc'),
      isTrue,
    );
    expect(isDirectEmbedVideo('https://cdn.test/live.m3u8'), isTrue);
  });

  test('official playback errors explain owner/private/referrer failures', () {
    expect(youtubePlaybackError(100), contains('unavailable or private'));
    expect(youtubePlaybackError(101), contains('owner'));
    expect(youtubePlaybackError(150), contains('owner'));
    expect(youtubePlaybackError(153), contains('verify'));
    expect(youtubePlaybackError(5), contains('YouTube'));
  });
}
