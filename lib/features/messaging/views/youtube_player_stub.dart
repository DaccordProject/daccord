import 'package:flutter/widgets.dart';
import 'package:bonfire/features/messaging/utils/youtube_video.dart';

const supportsYouTubePlayer = false;

class YouTubePlayer extends StatelessWidget {
  const YouTubePlayer({super.key, required this.video, required this.onStopped, required this.onError});
  final YouTubeVideo video;
  final VoidCallback onStopped;
  final ValueChanged<String> onError;
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
