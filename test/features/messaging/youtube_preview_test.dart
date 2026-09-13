import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/utils/youtube_video.dart';
import 'package:bonfire/features/messaging/views/box/accord_embed_box.dart';
import 'package:bonfire/features/messaging/views/inline_video_player.dart';
import 'package:bonfire/features/messaging/views/youtube_preview.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _video = YouTubeVideo.parse('https://youtu.be/dQw4w9WgXcQ')!;

Widget _host(Widget child, {double width = 440, bool ticking = true}) => ProviderScope(
  child: MaterialApp(
    theme: buildAppTheme(AppThemePreset.dark),
    home: Scaffold(body: Align(alignment: Alignment.topLeft,
      child: SizedBox(width: width, child: TickerMode(enabled: ticking, child: child)),
    )),
  ),
);

class _FakePlayer extends StatefulWidget {
  const _FakePlayer({required this.onDisposed});
  final VoidCallback onDisposed;
  @override
  State<_FakePlayer> createState() => _FakePlayerState();
}

class _FakePlayerState extends State<_FakePlayer> {
  @override
  void dispose() {
    widget.onDisposed();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => const Text('official player placeholder');
}

void main() {
  testWidgets('poster and iframe each require explicit third-party consent', (tester) async {
    var created = 0;
    await tester.pumpWidget(_host(YouTubePreview(
      video: _video, poster: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      cdnUrl: 'https://chat.example/cdn',
      playerBuilder: (_, _, _) { created++; return const Text('player'); },
    )));
    expect(created, 0);
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.text('Load external image from i.ytimg.com'), findsOneWidget);
    expect(find.textContaining('shares your connection with Google'), findsOneWidget);
    final size = tester.getSize(find.byType(AspectRatio));
    expect(size.width / size.height, closeTo(16 / 9, 0.001));
    await tester.tap(find.byKey(const ValueKey('youtube-play')));
    await tester.pump();
    expect(created, 1);
    expect(find.text('player'), findsOneWidget);
  });

  testWidgets('official playback errors restore the poster and external fallback', (tester) async {
    ValueChanged<String>? fail;
    var disposed = 0;
    await tester.pumpWidget(_host(YouTubePreview(video: _video,
      playerBuilder: (_, _, onError) {
        fail = onError;
        return _FakePlayer(onDisposed: () => disposed++);
      },
    )));
    await tester.tap(find.byKey(const ValueKey('youtube-play')));
    await tester.pump();
    fail!(youtubePlaybackError(150));
    await tester.pump();
    expect(disposed, 1);
    expect(find.byType(_FakePlayer), findsNothing);
    expect(find.textContaining('owner does not allow'), findsOneWidget);
    expect(find.text('Open in YouTube'), findsOneWidget);
    expect(find.byIcon(Icons.smart_display), findsOneWidget);
  });

  testWidgets('app backgrounding destroys playback without resuming automatically', (tester) async {
    var disposed = 0;
    await tester.pumpWidget(_host(YouTubePreview(video: _video,
      playerBuilder: (_, _, _) => _FakePlayer(onDisposed: () => disposed++),
    )));
    await tester.tap(find.byKey(const ValueKey('youtube-play')));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(disposed, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byType(_FakePlayer), findsNothing);
  });

  testWidgets('offscreen stop callback tears down player and keeps consent prompt', (tester) async {
    VoidCallback? stop;
    var disposed = 0;
    await tester.pumpWidget(_host(YouTubePreview(video: _video,
      playerBuilder: (_, onStopped, _) {
        stop = onStopped;
        return _FakePlayer(onDisposed: () => disposed++);
      },
    )));
    await tester.tap(find.byKey(const ValueKey('youtube-play')));
    await tester.pump();
    stop!();
    await tester.pump();
    expect(disposed, 1);
    expect(find.text('Play · load from YouTube'), findsOneWidget);
  });

  testWidgets('video changes, inactive routes and removal dispose playback', (tester) async {
    var disposed = 0;
    Widget preview(YouTubeVideo video) => YouTubePreview(video: video,
      playerBuilder: (_, _, _) => _FakePlayer(onDisposed: () => disposed++),
    );
    await tester.pumpWidget(_host(preview(_video)));
    await tester.tap(find.byKey(const ValueKey('youtube-play')));
    await tester.pump();
    await tester.pumpWidget(_host(preview(YouTubeVideo.parse('https://youtu.be/aaaaaaaaaaa')!)));
    expect(disposed, 1);
    await tester.tap(find.byKey(const ValueKey('youtube-play')));
    await tester.pump();
    await tester.pumpWidget(_host(preview(YouTubeVideo.parse('https://youtu.be/aaaaaaaaaaa')!), ticking: false));
    expect(disposed, 2);
    await tester.pumpWidget(_host(preview(_video)));
    await tester.tap(find.byKey(const ValueKey('youtube-play')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    expect(disposed, 3);
  });

  testWidgets('narrow columns fall back externally and cannot silently resume', (tester) async {
    var disposed = 0;
    Widget preview() => YouTubePreview(video: _video,
      playerBuilder: (_, _, _) => _FakePlayer(onDisposed: () => disposed++),
    );
    await tester.pumpWidget(_host(preview()));
    await tester.tap(find.byKey(const ValueKey('youtube-play')));
    await tester.pump();
    await tester.pumpWidget(_host(preview(), width: 300));
    expect(disposed, 1);
    expect(find.byKey(const ValueKey('youtube-play')), findsNothing);
    expect(find.text('Open in YouTube'), findsOneWidget);
    await tester.pumpWidget(_host(preview()));
    expect(find.byType(_FakePlayer), findsNothing);
  });

  testWidgets('native preview always offers safe external playback', (tester) async {
    await tester.pumpWidget(_host(YouTubePreview(video: _video)));
    expect(find.byKey(const ValueKey('youtube-play')), findsNothing);
    expect(find.text('Open in YouTube'), findsOneWidget);
    expect(find.byType(InlineVideoPlayer), findsNothing);
  });

  testWidgets('YouTube embeds retain title/provider/poster without a native decoder', (tester) async {
    await tester.pumpWidget(_host(AccordEmbedBox(embed: AccordEmbed(
      type: 'video', title: 'A video', url: _video.canonicalUrl,
      image: {'url': 'https://i.ytimg.com/poster.jpg'},
    ))));
    expect(find.text('A video'), findsOneWidget);
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.byType(YouTubePreview), findsOneWidget);
    expect(find.byType(InlineVideoPlayer), findsNothing);
    expect(find.byType(CachedNetworkImage), findsNothing);
  });

  testWidgets('untrusted provider HTML is never treated as native video', (tester) async {
    await tester.pumpWidget(_host(AccordEmbedBox(embed: AccordEmbed(
      type: 'video', url: 'https://youtube.com.evil.test/watch?v=dQw4w9WgXcQ',
      image: 'https://external.test/poster.jpg',
    ))));
    expect(find.byType(YouTubePreview), findsNothing);
    expect(find.byType(InlineVideoPlayer), findsNothing);
    expect(find.text('Load external image from external.test'), findsOneWidget);
  });
}
