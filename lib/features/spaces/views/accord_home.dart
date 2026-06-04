import 'package:accordkit/accordkit.dart';
import 'package:collection/collection.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// First Accord-native screen: a three-pane read view (space rail → channel
/// list → message history) wired to the Accord controllers. This is the
/// scaffold the firebridge UI is being migrated onto; it deliberately covers
/// only the read path (no DMs, folders, composer, or member resolution yet).
class AccordHomeScreen extends ConsumerStatefulWidget {
  const AccordHomeScreen({super.key});

  @override
  ConsumerState<AccordHomeScreen> createState() => _AccordHomeScreenState();
}

class _AccordHomeScreenState extends ConsumerState<AccordHomeScreen> {
  String? _selectedSpaceId;
  String? _selectedChannelId;

  void _selectSpace(String spaceId) {
    setState(() {
      _selectedSpaceId = spaceId;
      _selectedChannelId = null;
    });
  }

  void _selectChannel(String channelId) {
    setState(() => _selectedChannelId = channelId);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(accordAuthProvider, (previous, next) {
      if (next is! AccordAuthLoggedIn) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go('/');
        });
      }
    });

    final spaces = ref.watch(spacesControllerProvider);

    final selectedSpaceId = _selectedSpaceId ??
        ((spaces != null && spaces.isNotEmpty) ? spaces.first.id : null);

    final channels = selectedSpaceId == null
        ? null
        : ref.watch(accordChannelsControllerProvider(selectedSpaceId));

    final listableChannels =
        channels?.where((c) => c.type != 'category').toList();

    final firstText =
        listableChannels?.where((c) => c.type == 'text').firstOrNull;
    final selectedChannelId = _selectedChannelId ?? firstText?.id;

    return Row(
      children: [
        _SpaceRail(
          spaces: spaces,
          selectedSpaceId: selectedSpaceId,
          onSelect: _selectSpace,
          onLogout: () => ref.read(accordAuthProvider.notifier).logout(),
        ),
        _ChannelList(
          spaceName: spaces
              ?.where((s) => s.id == selectedSpaceId)
              .firstOrNull
              ?.name,
          channels: listableChannels,
          selectedChannelId: selectedChannelId,
          onSelect: _selectChannel,
        ),
        Expanded(
          child: _MessagePane(
            channel: channels?.where((c) => c.id == selectedChannelId).firstOrNull,
            channelId: selectedChannelId,
          ),
        ),
      ],
    );
  }
}

class _SpaceRail extends StatelessWidget {
  const _SpaceRail({
    required this.spaces,
    required this.selectedSpaceId,
    required this.onSelect,
    required this.onLogout,
  });

  final List<AccordSpace>? spaces;
  final String? selectedSpaceId;
  final ValueChanged<String> onSelect;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      width: 72,
      color: colors.background,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final space in spaces ?? const <AccordSpace>[])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: _SpaceIcon(
                      space: space,
                      selected: space.id == selectedSpaceId,
                      onTap: () => onSelect(space.id),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Log out',
            onPressed: onLogout,
            icon: Icon(Icons.logout, color: colors.dirtyWhite, size: 20),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SpaceIcon extends StatelessWidget {
  const _SpaceIcon({
    required this.space,
    required this.selected,
    required this.onTap,
  });

  final AccordSpace space;
  final bool selected;
  final VoidCallback onTap;

  String get _initials {
    final name = space.name.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Center(
      child: Tooltip(
        message: space.name,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: selected ? colors.primary : colors.darkGray,
              borderRadius: BorderRadius.circular(selected ? 16 : 24),
            ),
            alignment: Alignment.center,
            child: Text(
              _initials,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall!
                  .copyWith(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChannelList extends StatelessWidget {
  const _ChannelList({
    required this.spaceName,
    required this.channels,
    required this.selectedChannelId,
    required this.onSelect,
  });

  final String? spaceName;
  final List<AccordChannel>? channels;
  final String? selectedChannelId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: colors.foreground,
        border: Border(
          left: BorderSide(color: colors.background, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 48,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colors.background, width: 1),
              ),
            ),
            child: Text(
              spaceName ?? 'Select a space',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Expanded(
            child: channels == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      for (final channel in channels!)
                        _ChannelTile(
                          channel: channel,
                          selected: channel.id == selectedChannelId,
                          onTap: () => onSelect(channel.id),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.channel,
    required this.selected,
    required this.onTap,
  });

  final AccordChannel channel;
  final bool selected;
  final VoidCallback onTap;

  IconData get _glyph {
    switch (channel.type) {
      case 'voice':
        return Icons.volume_up;
      case 'forum':
        return Icons.forum;
      default:
        return Icons.tag;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final enabled = channel.type == 'text' || channel.type == 'forum';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected ? colors.darkGray : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Icon(_glyph,
                    size: 18,
                    color: enabled ? colors.dirtyWhite : colors.gray),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    channel.name ?? channel.id,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          color: enabled ? colors.dirtyWhite : colors.gray,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MessagePane extends ConsumerWidget {
  const _MessagePane({required this.channel, required this.channelId});

  final AccordChannel? channel;
  final String? channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);

    if (channelId == null) {
      return Container(
        color: colors.background,
        alignment: Alignment.center,
        child: Text('Select a channel',
            style: Theme.of(context).textTheme.bodyMedium),
      );
    }

    final messages = ref.watch(accordMessagesControllerProvider(channelId!));

    return Container(
      color: colors.background,
      child: Column(
        children: [
          Container(
            height: 48,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colors.foreground, width: 1),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.tag, size: 18, color: colors.dirtyWhite),
                const SizedBox(width: 6),
                Text(channel?.name ?? '',
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
          ),
          Expanded(
            child: messages == null
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                    ? Center(
                        child: Text('No messages yet',
                            style: Theme.of(context).textTheme.bodyMedium),
                      )
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[messages.length - 1 - index];
                          return _MessageRow(message: message);
                        },
                      ),
          ),
          _ComposerPlaceholder(),
        ],
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.message});

  final AccordMessage message;

  String get _time {
    final dt = DateTime.tryParse(message.timestamp);
    if (dt == null) return '';
    final local = dt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                // TODO: resolve author via a member/user cache (not built yet).
                message.authorId,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(width: 8),
              Text(_time,
                  style: theme.textTheme.labelMedium!
                      .copyWith(color: colors.gray)),
            ],
          ),
          if (message.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(message.content, style: theme.textTheme.bodyLarge),
            ),
          for (final attachment in message.attachments)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('📎 ${attachment.filename}',
                  style: theme.textTheme.bodyMedium),
            ),
        ],
      ),
    );
  }
}

class _ComposerPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        height: 44,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: colors.darkGray,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Sending messages isn’t wired up yet',
          style: Theme.of(context)
              .textTheme
              .bodyMedium!
              .copyWith(color: colors.gray),
        ),
      ),
    );
  }
}
