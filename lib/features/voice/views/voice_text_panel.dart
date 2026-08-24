import 'package:bonfire/shared/utils/client_access.dart';
import 'package:accordkit/accordkit.dart' show AccordChannel;
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/channels/utils/mark_channel_read.dart';
import 'package:bonfire/features/messaging/views/message_pane/message_pane.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Text chat for a voice channel, shown beside (or over) the video grid while in
/// a voice call. Ports the reference client's dedicated `voice_text_panel.gd`.
///
/// A voice channel's chat is an ordinary text channel, so this is a thin
/// wrapper around [MessagePane] in its panel presentation rather than a
/// second, slimmer message list. That was the bug (#210): the hand-rolled panel
/// rendered author + content and nothing else, so voice chat silently lost the
/// context menu, reactions, replies, threads, edit/delete/pin/report,
/// attachments, embeds, timestamps, mention highlighting, history paging and
/// the full composer that every other channel has. The only things this widget
/// still owns are the voice-specific bits: acking the channel on open (against
/// the connection the *call* is pinned to, which needn't be the active one) and
/// the panel's title/close button.
class VoiceTextPanel extends ConsumerStatefulWidget {
  const VoiceTextPanel({
    super.key,
    required this.channelId,
    required this.spaceId,
    required this.channelName,
    this.onClose,
  });

  final String channelId;
  final String? spaceId;
  final String? channelName;

  /// Called when the user taps the panel's close button. When null the close
  /// button is hidden (e.g. when the panel is the whole surface).
  final VoidCallback? onClose;

  @override
  ConsumerState<VoiceTextPanel> createState() => _VoiceTextPanelState();
}

class _VoiceTextPanelState extends ConsumerState<VoiceTextPanel> {
  @override
  void initState() {
    super.initState();
    // Opening the panel clears the voice channel's unread state, mirroring the
    // reference's `Client.clear_channel_unread`. This acks to the server too —
    // a local-only clear comes back on the next connect via READY's `unread`.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The panel's channel lives on whichever server the call is pinned to,
      // which may not be the active one.
      final serverKey = ref.read(voiceControllerProvider).serverKey ??
          ref.read(connectionsControllerProvider).activeKey;
      markChannelRead(
        ref,
        widget.channelId,
        serverKey: serverKey,
        fallbackMessageId: _channel()?.lastMessageId,
      );
    });
  }

  /// The panel's channel from the space's channel cache. Supplies the ack
  /// position (`last_message_id`) before this panel's own history has loaded,
  /// and the channel the pane renders (for permissions and the header).
  AccordChannel? _channel() {
    final spaceId = widget.spaceId;
    if (spaceId == null) return null;
    return ref
        .read(accordChannelsControllerProvider(ref.readActiveServerKey() ?? '', spaceId))
        ?.firstWhereOrNull((c) => c.id == widget.channelId);
  }

  @override
  Widget build(BuildContext context) {
    final spaceId = widget.spaceId;
    final channel = spaceId == null
        ? null
        : ref.watch(accordChannelsControllerProvider(ref.readActiveServerKey() ?? '', spaceId).select(
            (channels) =>
                channels?.firstWhereOrNull((c) => c.id == widget.channelId),
          ));
    return MessagePane(
      channel: channel,
      channelId: widget.channelId,
      spaceId: spaceId,
      panel: true,
      panelTitle: widget.channelName ?? channel?.name,
      onClosePanel: widget.onClose,
    );
  }
}
