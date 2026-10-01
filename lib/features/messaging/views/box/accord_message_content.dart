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
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:collection/collection.dart';
import 'package:dart_markdown/dart_markdown.dart' as md;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'accord_message_content.g.dart';

/// Without a space nothing resolves against space caches, so every DM row can
/// share one list.
final _noSpaceSyntaxes = accordMarkupSyntaxes();

/// Keep syntax identity stable so MarkdownViewer retains its parse on rebuild.
/// Only mention-bearing content loads the member roster; fetching it backfills
/// each member even when the sidebar is collapsed.
@riverpod
List<md.Syntax> _spaceMarkupSyntaxes(
  Ref ref,
  String serverKey,
  String spaceId,
  String? cdnUrl, {
  required bool withMembers,
}) {
  final members = withMembers
      ? ref.watch(accordMembersControllerProvider(serverKey, spaceId))
      : null;
  final roles = ref.watch(
    spacesControllerProvider.select(
      (s) => s?.firstWhereOrNull((sp) => sp.id == spaceId)?.roles,
    ),
  );
  final channels = ref.watch(
    accordChannelsControllerProvider(serverKey, spaceId),
  );
  final emojis = ref.watch(accordEmojisControllerProvider(serverKey, spaceId));

  final userByHandle = <String, AccordMember>{};
  for (final member in members?.values ?? const <AccordMember>[]) {
    for (final handle in [member.user?.username, member.user?.displayName]) {
      if (handle != null && handle.isNotEmpty) {
        userByHandle.putIfAbsent(handle.toLowerCase(), () => member);
      }
    }
  }
  final channelByName = <String, AccordChannel>{};
  for (final channel in channels ?? const <AccordChannel>[]) {
    final name = channel.name;
    if (name != null && name.isNotEmpty && channel.type != 'category') {
      channelByName.putIfAbsent(name.toLowerCase(), () => channel);
    }
  }
  return accordMarkupSyntaxes(
    AccordMarkupContext(
      userByHandle: userByHandle,
      roleByName: {
        for (final role in roles ?? const <AccordRole>[])
          if (role.mentionable && role.name.isNotEmpty)
            role.name.toLowerCase(): role,
      },
      channelByName: channelByName,
      emojiByName: {
        for (final e in emojis ?? const <AccordEmoji>[])
          if (e.name.isNotEmpty) e.name.toLowerCase(): e,
      },
      cdnUrl: cdnUrl,
    ),
  );
}

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
    return AccordMarkdownBox(
      content: content,
      trustedMediaBaseUrl: cdnUrl,
      syntaxExtensions: id == null
          ? _noSpaceSyntaxes
          : ref.watch(
              _spaceMarkupSyntaxesProvider(
                ref.readActiveServerKey() ?? '',
                id,
                cdnUrl,
                withMembers: content.contains('@'),
              ),
            ),
      elementBuilders: accordMarkupBuilders(
        cdnUrl: cdnUrl,
        onTapUser: id == null
            ? null
            : (userId) =>
                  showAccordMemberPopout(context, spaceId: id, userId: userId),
        onTapChannel: id == null
            ? null
            : (channelId) => _openChannel(ref, id, channelId),
      ),
    );
  }

  /// Opens (or switches to) the tab for [channelId] on the active server,
  /// mirroring the sidebar's channel selection. The NSFW gate and voice-join
  /// behaviour stay with the message pane / channel list; a mention tap just
  /// surfaces the channel.
  void _openChannel(WidgetRef ref, String spaceId, String channelId) {
    final activeKey = ref.readActiveServerKey();
    if (activeKey == null) return;
    final channel = ref
        .read(accordChannelsControllerProvider(activeKey, spaceId))
        ?.firstWhereOrNull((c) => c.id == channelId);
    ref
        .read(openTabsControllerProvider.notifier)
        .open(
          OpenTab(
            channelId: channelId,
            spaceId: spaceId,
            serverKey: activeKey,
            name: channel?.name ?? channelId,
          ),
        );
    markChannelRead(ref, channelId, fallbackMessageId: channel?.lastMessageId);
    ref
        .read(settingsControllerProvider.notifier)
        .setLastSelection(activeKey, spaceId, channelId);
  }
}
