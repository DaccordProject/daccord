import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/channels/controllers/open_tabs.dart';
import 'package:bonfire/features/channels/utils/mark_channel_read.dart';
import 'package:bonfire/features/channels/models/open_tab.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/views/accord_member_popout.dart';
import 'package:bonfire/features/messaging/views/box/accord_markdown_box.dart';
import 'package:bonfire/features/messaging/views/box/accord_message_markup.dart';
import 'package:bonfire/features/messaging/controllers/accord_emojis.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Renders Accord message content as markdown, with inline chips for `@user`,
/// `@role`, `@everyone`/`@here`, and `#channel` references, custom `:emoji:`,
/// `||spoiler||` reveals, and `__underline__`.
///
/// All of these are layered onto the standard markdown stack ([AccordMarkdownBox])
/// as syntax extensions, so a single message renders markdown *and* Accord
/// tokens together. Mention/channel chips are tappable: a user mention opens the
/// member popout, a channel mention opens (or focuses) that channel's tab.
///
/// Pass [spaceId] when rendering inside a space so handles resolve against the
/// space's caches and taps can navigate; without it (DMs) only the
/// protocol-agnostic tokens (`@everyone`/`@here`, spoiler, underline, markdown)
/// apply.
class AccordMessageContent extends ConsumerWidget {
  const AccordMessageContent({super.key, required this.content, this.spaceId});

  final String content;
  final String? spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cdnUrl = ref.watchCdnUrl();

    final id = spaceId;
    if (id == null) {
      // DM / no-space context: still resolve broadcasts, spoilers, underline,
      // and markdown — just nothing that needs space caches or navigation.
      final markup = buildAccordMarkup(AccordMarkupContext(cdnUrl: cdnUrl));
      return AccordMarkdownBox(
        content: content,
        trustedMediaBaseUrl: cdnUrl,
        syntaxExtensions: markup.syntaxes,
        elementBuilders: markup.builders,
      );
    }

    // The member roster is only consulted to resolve `@handle` mentions, and
    // backfilling it fans out a fetch per member. Most messages contain no
    // mention, so skip the load entirely unless this one does — that keeps a
    // mention-free channel from triggering the roster fetch when the member
    // sidebar (which loads it on its own) is collapsed.
    final members = content.contains('@')
        ? ref.watch(accordMembersControllerProvider(id))
        : null;
    final space = ref.watch(
      spacesControllerProvider.select(
        (s) => s?.firstWhereOrNull((sp) => sp.id == id),
      ),
    );
    final channels = ref.watch(accordChannelsControllerProvider(id));
    final emojiList = ref.watch(accordEmojisControllerProvider(id));

    final userByHandle = <String, AccordMember>{};
    if (members != null) {
      for (final member in members.values) {
        final username = member.user?.username;
        if (username != null && username.isNotEmpty) {
          userByHandle.putIfAbsent(username.toLowerCase(), () => member);
        }
        final display = member.user?.displayName;
        if (display != null && display.isNotEmpty) {
          userByHandle.putIfAbsent(display.toLowerCase(), () => member);
        }
      }
    }

    final roleByName = <String, AccordRole>{
      for (final role in (space?.roles ?? const <AccordRole>[]))
        if (role.mentionable && role.name.isNotEmpty)
          role.name.toLowerCase(): role,
    };

    final channelByName = <String, AccordChannel>{};
    for (final channel in (channels ?? const <AccordChannel>[])) {
      final name = channel.name;
      if (name != null && name.isNotEmpty && channel.type != 'category') {
        channelByName.putIfAbsent(name.toLowerCase(), () => channel);
      }
    }

    final emojiByName = <String, AccordEmoji>{
      for (final e in (emojiList ?? const <AccordEmoji>[]))
        if (e.name.isNotEmpty) e.name.toLowerCase(): e,
    };

    final markup = buildAccordMarkup(
      AccordMarkupContext(
        userByHandle: userByHandle,
        roleByName: roleByName,
        channelByName: channelByName,
        emojiByName: emojiByName,
        cdnUrl: cdnUrl,
        onTapUser: (userId) =>
            showAccordMemberPopout(context, spaceId: id, userId: userId),
        onTapChannel: (channelId) => _openChannel(ref, id, channelId),
      ),
    );

    return AccordMarkdownBox(
      content: content,
      trustedMediaBaseUrl: cdnUrl,
      syntaxExtensions: markup.syntaxes,
      elementBuilders: markup.builders,
    );
  }

  /// Opens (or switches to) the tab for [channelId] on the active server,
  /// mirroring the sidebar's channel selection. The NSFW gate and voice-join
  /// behaviour stay with the message pane / channel list; a mention tap just
  /// surfaces the channel.
  void _openChannel(WidgetRef ref, String spaceId, String channelId) {
    final activeKey = ref.read(connectionsControllerProvider).activeKey;
    if (activeKey == null) return;
    final channel = ref
        .read(accordChannelsControllerProvider(spaceId))
        ?.firstWhereOrNull((c) => c.id == channelId);
    ref.read(openTabsControllerProvider.notifier).open(
          OpenTab(
            channelId: channelId,
            spaceId: spaceId,
            serverKey: activeKey,
            name: channel?.name ?? channelId,
          ),
        );
    markChannelRead(ref, channelId,
        fallbackMessageId: channel?.lastMessageId);
    ref.read(settingsControllerProvider.notifier).setLastSelection(
          spaceId,
          channelId,
        );
  }
}
