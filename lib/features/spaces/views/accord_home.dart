import 'package:accordkit/accordkit.dart';
import 'package:collection/collection.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/member/views/accord_member_list.dart';
import 'package:bonfire/features/messaging/components/box/accord_embed_box.dart';
import 'package:bonfire/features/messaging/components/box/accord_markdown_box.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/messaging/controllers/typing.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
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
    final cdnUrl = ref.watch(
      accordAuthProvider.select(
          (s) => s is AccordAuthLoggedIn ? s.session.server.cdnUrl : null),
    );

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
          cdnUrl: cdnUrl,
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
            spaceId: selectedSpaceId,
          ),
        ),
        if (selectedSpaceId != null) AccordMemberList(spaceId: selectedSpaceId),
      ],
    );
  }
}

class _SpaceRail extends StatelessWidget {
  const _SpaceRail({
    required this.spaces,
    required this.selectedSpaceId,
    required this.cdnUrl,
    required this.onSelect,
    required this.onLogout,
  });

  final List<AccordSpace>? spaces;
  final String? selectedSpaceId;
  final String? cdnUrl;
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
                      cdnUrl: cdnUrl,
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
    required this.cdnUrl,
    required this.onTap,
  });

  final AccordSpace space;
  final bool selected;
  final String? cdnUrl;
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
    final iconUrl = _spaceIconUrl(space, cdnUrl);
    final radius = BorderRadius.circular(selected ? 16 : 24);
    final fallback = Text(
      _initials,
      style:
          Theme.of(context).textTheme.titleSmall!.copyWith(color: Colors.white),
    );
    return Center(
      child: Tooltip(
        message: space.name,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 48,
            height: 48,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: selected ? colors.primary : colors.darkGray,
              borderRadius: radius,
            ),
            alignment: Alignment.center,
            child: iconUrl == null
                ? fallback
                : CachedNetworkImage(
                    imageUrl: iconUrl,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => fallback,
                    errorWidget: (_, _, _) => fallback,
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
  const _MessagePane({
    required this.channel,
    required this.channelId,
    required this.spaceId,
  });

  final AccordChannel? channel;
  final String? channelId;
  final String? spaceId;

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
    final members = spaceId == null
        ? null
        : ref.watch(accordMembersControllerProvider(spaceId!));
    final roles = spaceId == null
        ? const <AccordRole>[]
        : ref.watch(
            spacesControllerProvider.select(
              (spaces) =>
                  spaces?.firstWhereOrNull((s) => s.id == spaceId)?.roles ??
                  const <AccordRole>[],
            ),
          );
    final currentUserId = ref.watch(
      accordAuthProvider.select(
          (s) => s is AccordAuthLoggedIn ? s.session.userId : null),
    );

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
                          final author = members?[message.authorId];
                          final colorRole = author == null
                              ? null
                              : memberColorRole(author, roles);
                          return _MessageRow(
                            message: message,
                            author: author,
                            nameColor: colorRole == null
                                ? null
                                : accordRoleColor(colorRole.color),
                            channelId: channelId!,
                            isOwn: currentUserId != null &&
                                message.authorId == currentUserId,
                          );
                        },
                      ),
          ),
          _TypingIndicator(channelId: channelId!, spaceId: spaceId),
          _Composer(channelId: channelId!, channelName: channel?.name),
        ],
      ),
    );
  }
}

/// A thin "X is typing…" line above the composer, resolving typing user IDs to
/// names via the space's member cache.
class _TypingIndicator extends ConsumerWidget {
  const _TypingIndicator({required this.channelId, required this.spaceId});

  final String channelId;
  final String? spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final typing = ref.watch(typingControllerProvider(channelId));
    final members = spaceId == null
        ? null
        : ref.watch(accordMembersControllerProvider(spaceId!));

    String nameFor(String userId) =>
        accordMemberName(members?[userId], fallback: 'Someone');

    String? label;
    if (typing.length == 1) {
      label = '${nameFor(typing.first)} is typing…';
    } else if (typing.length == 2) {
      label = '${nameFor(typing[0])} and ${nameFor(typing[1])} are typing…';
    } else if (typing.length > 2) {
      label = 'Several people are typing…';
    }

    return SizedBox(
      height: 20,
      child: label == null
          ? null
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium!
                      .copyWith(color: colors.gray),
                ),
              ),
            ),
    );
  }
}

class _MessageRow extends ConsumerStatefulWidget {
  const _MessageRow({
    required this.message,
    required this.channelId,
    required this.isOwn,
    this.author,
    this.nameColor,
  });

  final AccordMessage message;
  final String channelId;

  /// Whether this message belongs to the current user (gates edit/delete).
  final bool isOwn;

  /// The resolved member for [AccordMessage.authorId], if the space's member
  /// cache has loaded. `null` falls back to the raw author ID.
  final AccordMember? author;

  /// The author's highest colored-role color, or null for the default color.
  final Color? nameColor;

  @override
  ConsumerState<_MessageRow> createState() => _MessageRowState();
}

class _MessageRowState extends ConsumerState<_MessageRow> {
  bool _hovered = false;
  bool _editing = false;
  bool _busy = false;
  TextEditingController? _editController;

  AccordMessage get _message => widget.message;

  @override
  void dispose() {
    _editController?.dispose();
    super.dispose();
  }

  String get _time {
    final dt = DateTime.tryParse(_message.timestamp);
    if (dt == null) return '';
    final local = dt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  /// Nickname → user display name → username → raw ID.
  String get _authorName =>
      accordMemberName(widget.author, fallback: _message.authorId);

  String get _initial {
    final name = _authorName.trim();
    if (name.isEmpty) return '?';
    return name.substring(0, 1).toUpperCase();
  }

  AccordClient? get _client => ref.read(
        accordAuthProvider
            .select((s) => s is AccordAuthLoggedIn ? s.client : null),
      );

  void _startEdit() {
    setState(() {
      _editing = true;
      _editController = TextEditingController(text: _message.content);
    });
  }

  void _cancelEdit() {
    setState(() {
      _editing = false;
      _editController?.dispose();
      _editController = null;
    });
  }

  Future<void> _saveEdit() async {
    final client = _client;
    final text = _editController?.text ?? '';
    if (client == null || text.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    final ok = await ref
        .read(accordMessagesControllerProvider(widget.channelId).notifier)
        .edit(client, _message.id, text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) _cancelEdit();
  }

  void _toggleReaction(String emojiName) {
    final client = _client;
    if (client == null) return;
    ref
        .read(accordMessagesControllerProvider(widget.channelId).notifier)
        .toggleReaction(client, _message.id, emojiName);
  }

  Future<void> _delete() async {
    final client = _client;
    if (client == null || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message'),
        content: const Text('This message will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    await ref
        .read(accordMessagesControllerProvider(widget.channelId).notifier)
        .delete(client, _message.id);
    // Row disappears on success; if it failed we just re-enable.
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final cdnUrl = ref.watch(
      accordAuthProvider.select(
          (s) => s is AccordAuthLoggedIn ? s.session.server.cdnUrl : null),
    );
    final avatarUrl = accordAvatarUrl(widget.author?.user, cdnUrl);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: colors.darkGray,
              foregroundImage:
                  avatarUrl == null ? null : CachedNetworkImageProvider(avatarUrl),
              child: Text(
                _initial,
                style: theme.textTheme.titleSmall!.copyWith(color: Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(_authorName,
                          style: theme.textTheme.titleSmall!
                              .copyWith(color: widget.nameColor)),
                      const SizedBox(width: 8),
                      Text(_time,
                          style: theme.textTheme.labelMedium!
                              .copyWith(color: colors.gray)),
                      if (_message.editedAt != null) ...[
                        const SizedBox(width: 6),
                        Text('(edited)',
                            style: theme.textTheme.labelSmall!
                                .copyWith(color: colors.gray)),
                      ],
                    ],
                  ),
                  if (_editing)
                    _buildEditor(theme, colors)
                  else if (_message.content.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: AccordMarkdownBox(content: _message.content),
                    ),
                  for (final attachment in _message.attachments)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _isImageAttachment(attachment)
                          ? _ImageAttachment(
                              url: _attachmentUrl(attachment, cdnUrl),
                              width: _asDouble(attachment.width),
                              height: _asDouble(attachment.height),
                            )
                          : Text('📎 ${attachment.filename}',
                              style: theme.textTheme.bodyMedium),
                    ),
                  for (final embed in _message.embeds)
                    AccordEmbedBox(embed: embed, cdnUrl: cdnUrl),
                  if ((_message.reactions ?? const []).isNotEmpty)
                    _buildReactions(theme, colors),
                ],
              ),
            ),
            if (!_editing)
              Opacity(
                opacity: _hovered ? 1 : 0,
                child: Row(
                  children: [
                    _ReactButton(onPick: _toggleReaction),
                    if (widget.isOwn)
                      _MessageActions(onEdit: _startEdit, onDelete: _delete),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReactions(ThemeData theme, BonfireThemeExtension colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final reaction in _message.reactions!)
            _ReactionPill(
              reaction: reaction,
              onTap: () =>
                  _toggleReaction(reaction.emoji['name']?.toString() ?? ''),
            ),
        ],
      ),
    );
  }

  Widget _buildEditor(ThemeData theme, BonfireThemeExtension colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _editController,
            autofocus: true,
            enabled: !_busy,
            minLines: 1,
            maxLines: 6,
            style: theme.textTheme.bodyLarge,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: colors.darkGray,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (_) => _saveEdit(),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton(
                onPressed: _busy ? null : _cancelEdit,
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: _busy ? null : _saveEdit,
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageActions extends StatelessWidget {
  const _MessageActions({required this.onEdit, required this.onDelete});

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Message actions',
      icon: Icon(Icons.more_horiz, size: 18, color: colors.gray),
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit();
          case 'delete':
            onDelete();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'edit', child: Text('Edit')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }
}

/// A small quick-reaction picker offering a handful of common unicode emoji.
class _ReactButton extends StatelessWidget {
  const _ReactButton({required this.onPick});

  final ValueChanged<String> onPick;

  static const _common = ['👍', '❤️', '😂', '🎉', '😮', '😢', '🔥'];

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Add reaction',
      icon: Icon(Icons.add_reaction_outlined, size: 18, color: colors.gray),
      onSelected: onPick,
      itemBuilder: (context) => [
        for (final emoji in _common)
          PopupMenuItem(
            value: emoji,
            child: Text(emoji, style: const TextStyle(fontSize: 20)),
          ),
      ],
    );
  }
}

class _ReactionPill extends StatelessWidget {
  const _ReactionPill({required this.reaction, required this.onTap});

  final AccordReaction reaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final name = reaction.emoji['name']?.toString() ?? '';
    final mine = reaction.includesMe;
    return Material(
      color: mine ? colors.primary.withValues(alpha: 0.25) : colors.darkGray,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: mine ? colors.primary : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
              Text('${reaction.count}',
                  style: theme.textTheme.labelMedium!
                      .copyWith(color: colors.dirtyWhite)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends ConsumerStatefulWidget {
  const _Composer({required this.channelId, this.channelName});

  final String channelId;
  final String? channelName;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _sending = false;

  /// Files the user has attached but not yet sent.
  final List<PlatformFile> _attachments = [];

  /// The server's typing indicator lasts ~10s, so we re-trigger at most once
  /// every 8s while the user keeps typing rather than on every keystroke.
  DateTime? _lastTypingSent;
  static const _typingInterval = Duration(seconds: 8);

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    if (value.trim().isEmpty) return;
    final now = DateTime.now();
    if (_lastTypingSent != null &&
        now.difference(_lastTypingSent!) < _typingInterval) {
      return;
    }
    _lastTypingSent = now;
    final client = ref.read(
      accordAuthProvider
          .select((s) => s is AccordAuthLoggedIn ? s.client : null),
    );
    client?.messages.typing(widget.channelId);
  }

  Future<void> _pickFiles() async {
    final result =
        await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
    if (result == null || !mounted) return;
    setState(() {
      for (final file in result.files) {
        if (file.bytes != null) _attachments.add(file);
      }
    });
  }

  void _removeAttachment(PlatformFile file) {
    setState(() => _attachments.remove(file));
  }

  Future<void> _send() async {
    final text = _controller.text;
    if ((text.trim().isEmpty && _attachments.isEmpty) || _sending) return;

    final client = ref.read(
      accordAuthProvider
          .select((s) => s is AccordAuthLoggedIn ? s.client : null),
    );
    if (client == null) return;

    setState(() => _sending = true);
    final controller =
        ref.read(accordMessagesControllerProvider(widget.channelId).notifier);
    final bool ok;
    if (_attachments.isEmpty) {
      ok = await controller.send(client, text);
    } else {
      final files = [
        for (final file in _attachments)
          {
            'filename': file.name,
            'content': file.bytes!,
            'content_type': _mimeType(file.extension),
          },
      ];
      ok = await controller.sendWithAttachments(client, text, files);
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (ok) _attachments.clear();
    });
    if (ok) {
      _controller.clear();
      _lastTypingSent = null;
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final hint = widget.channelName != null
        ? 'Message #${widget.channelName}'
        : 'Message';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: colors.darkGray,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final file in _attachments)
                      _AttachmentChip(
                        file: file,
                        onRemove:
                            _sending ? null : () => _removeAttachment(file),
                      ),
                  ],
                ),
              ),
            Row(
              children: [
                IconButton(
                  tooltip: 'Attach files',
                  onPressed: _sending ? null : _pickFiles,
                  icon: Icon(Icons.add_circle_outline,
                      size: 20, color: colors.dirtyWhite),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    enabled: !_sending,
                    minLines: 1,
                    maxLines: 6,
                    textInputAction: TextInputAction.send,
                    onChanged: _onChanged,
                    onSubmitted: (_) => _send(),
                    style: Theme.of(context).textTheme.bodyLarge,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: hint,
                      hintStyle: Theme.of(context)
                          .textTheme
                          .bodyLarge!
                          .copyWith(color: colors.gray),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Send',
                  onPressed: _sending ? null : _send,
                  icon: Icon(Icons.send, size: 20, color: colors.dirtyWhite),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Resolves a space's `icon` reference to an absolute CDN URL, or null when the
/// space has no icon. The field is either a bare asset hash or a
/// server-relative/absolute path; both are handled.
String? _spaceIconUrl(AccordSpace space, String? cdnUrl) {
  final icon = space.icon;
  if (icon is! String || icon.isEmpty) return null;
  final cdn = cdnUrl ?? '';
  if (icon.contains('/') || icon.startsWith('http')) {
    return AccordCDN.resolvePath(icon, cdnUrl: cdn);
  }
  return AccordCDN.spaceIcon(space.id, icon,
      format: AccordCDN.autoFormat(icon), cdnUrl: cdn);
}

/// Resolves an attachment's server-returned URL/path to an absolute CDN URL.
String _attachmentUrl(AccordAttachment attachment, String? cdnUrl) =>
    AccordCDN.resolvePath(attachment.url, cdnUrl: cdnUrl ?? '');

/// Whether an attachment should render as an inline image (by content type,
/// falling back to the filename extension).
bool _isImageAttachment(AccordAttachment attachment) {
  final type = attachment.contentType;
  if (type != null && type.startsWith('image/')) return true;
  final name = attachment.filename.toLowerCase();
  return name.endsWith('.png') ||
      name.endsWith('.jpg') ||
      name.endsWith('.jpeg') ||
      name.endsWith('.gif') ||
      name.endsWith('.webp');
}

/// Best-effort conversion of an attachment's loosely-typed width/height to a
/// double for sizing hints.
double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

/// Maps a file extension to a MIME type for attachment uploads, falling back to
/// a generic binary type when unknown.
String _mimeType(String? extension) {
  switch (extension?.toLowerCase()) {
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'svg':
      return 'image/svg+xml';
    case 'mp4':
      return 'video/mp4';
    case 'webm':
      return 'video/webm';
    case 'mp3':
      return 'audio/mpeg';
    case 'ogg':
      return 'audio/ogg';
    case 'wav':
      return 'audio/wav';
    case 'pdf':
      return 'application/pdf';
    case 'txt':
      return 'text/plain';
    case 'json':
      return 'application/json';
    case 'zip':
      return 'application/zip';
    default:
      return 'application/octet-stream';
  }
}

/// A removable chip representing one pending attachment in the composer.
class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.file, this.onRemove});

  final PlatformFile file;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: colors.foreground.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file_outlined,
              size: 16, color: colors.dirtyWhite),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              file.name,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall!
                  .copyWith(color: colors.dirtyWhite),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(12),
            child: Icon(Icons.close, size: 16, color: colors.gray),
          ),
        ],
      ),
    );
  }
}

/// An inline image attachment, constrained to a readable size and preserving
/// the server-provided aspect ratio when available.
class _ImageAttachment extends StatelessWidget {
  const _ImageAttachment({required this.url, this.width, this.height});

  final String url;
  final double? width;
  final double? height;

  static const _maxWidth = 400.0;
  static const _maxHeight = 350.0;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    double? renderWidth = width;
    double? renderHeight = height;
    if (renderWidth != null && renderWidth > _maxWidth) {
      final scale = _maxWidth / renderWidth;
      renderWidth = _maxWidth;
      if (renderHeight != null) renderHeight *= scale;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: _maxWidth,
          maxHeight: _maxHeight,
        ),
        child: CachedNetworkImage(
          imageUrl: url,
          width: renderWidth,
          height: renderHeight,
          fit: BoxFit.cover,
          placeholder: (_, _) => Container(
            width: renderWidth ?? 200,
            height: renderHeight ?? 150,
            color: colors.darkGray,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          errorWidget: (_, _, _) => Container(
            padding: const EdgeInsets.all(8),
            color: colors.darkGray,
            child: Icon(Icons.broken_image_outlined, color: colors.gray),
          ),
        ),
      ),
    );
  }
}
