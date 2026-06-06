import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/messaging/components/box/accord_message_content.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Relationship type enum mirrored from the server: 1 = friend, 2 = blocked,
/// 3 = pending incoming, 4 = pending outgoing.
class _Rel {
  static const friend = 1;
  static const pendingIn = 3;
  static const pendingOut = 4;
}

/// Best display name for a user.
String _userName(AccordUser? user) {
  if (user == null) return 'Unknown';
  final display = user.displayName;
  if (display != null && display.isNotEmpty) return display;
  return user.username.isNotEmpty ? user.username : user.id;
}

/// The recipients of [channel] excluding the current user.
List<AccordUser> _others(AccordChannel channel, String? selfId) =>
    (channel.recipients ?? const <AccordUser>[])
        .where((u) => u.id != selfId)
        .toList();

/// Whether [channel] is a group DM (3+ participants). Accord types DM channels
/// as `dm` (1:1) or `group_dm`; we also fall back to the recipient count since
/// some payloads omit the type.
bool _isGroup(AccordChannel channel, String? selfId) =>
    channel.type == 'group_dm' || _others(channel, selfId).length > 1;

/// Title for a DM/group channel: a group's custom name, else the joined
/// recipient names.
String _channelTitle(AccordChannel channel, String? selfId) {
  final name = channel.name;
  if (name != null && name.isNotEmpty) return name;
  final others = _others(channel, selfId);
  if (others.isEmpty) return 'Direct message';
  return others.map(_userName).join(', ');
}

/// Opens the direct-messages & friends panel: a tabbed dialog with the user's DM
/// conversations and their friends list (with requests). The Accord analogue of
/// the reference client's `dm_list` + `friends_list`.
Future<void> showAccordDirectMessages(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _DirectMessagesDialog(),
  );
}

class _DirectMessagesDialog extends ConsumerStatefulWidget {
  const _DirectMessagesDialog();

  @override
  ConsumerState<_DirectMessagesDialog> createState() =>
      _DirectMessagesDialogState();
}

class _DirectMessagesDialogState extends ConsumerState<_DirectMessagesDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  AccordChannel? _openChannel;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String? get _selfId => ref.read(accordAuthProvider
      .select((s) => s is AccordAuthLoggedIn ? s.session.userId : null));

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final openChannel = _openChannel;
    return Dialog(
      backgroundColor: colors.foreground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
        child: openChannel != null
            ? _DmConversation(
                channel: openChannel,
                selfId: _selfId,
                onBack: () => setState(() => _openChannel = null),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('Direct messages',
                              style: theme.textTheme.titleMedium),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Icon(Icons.close, size: 20, color: colors.gray),
                        ),
                      ],
                    ),
                  ),
                  TabBar(
                    controller: _tabs,
                    tabs: const [
                      Tab(text: 'Messages'),
                      Tab(text: 'Friends'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabs,
                      children: [
                        _DmListTab(
                          selfId: _selfId,
                          onOpen: (c) => setState(() => _openChannel = c),
                        ),
                        const _FriendsTab(),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _DmListTab extends ConsumerStatefulWidget {
  const _DmListTab({required this.selfId, required this.onOpen});

  final String? selfId;
  final ValueChanged<AccordChannel> onOpen;

  @override
  ConsumerState<_DmListTab> createState() => _DmListTabState();
}

class _DmListTabState extends ConsumerState<_DmListTab> {
  List<AccordChannel>? _channels;

  @override
  void initState() {
    super.initState();
    _load();
  }

  AccordClient? get _client => ref.read(accordAuthProvider
      .select((s) => s is AccordAuthLoggedIn ? s.client : null));

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    final result = await client.users.listChannels();
    if (!mounted) return;
    final data = result.data;
    setState(() {
      _channels = data is List
          ? data.whereType<AccordChannel>().toList()
          : <AccordChannel>[];
    });
  }

  Future<void> _createGroup() async {
    final channel = await showDialog<AccordChannel>(
      context: context,
      builder: (_) => const _CreateGroupDialog(),
    );
    if (channel == null || !mounted) return;
    await _load();
    if (mounted) widget.onOpen(channel);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final channels = _channels;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _createGroup,
              icon: const Icon(Icons.group_add, size: 18),
              label: const Text('New group'),
            ),
          ),
        ),
        Expanded(
          child: channels == null
              ? const Center(child: CircularProgressIndicator())
              : channels.isEmpty
                  ? Center(
                      child: Text('No direct messages yet',
                          style: theme.textTheme.bodyMedium))
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: channels.length,
                      itemBuilder: (context, index) {
                        final channel = channels[index];
                        final title = _channelTitle(channel, widget.selfId);
                        final group = _isGroup(channel, widget.selfId);
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: colors.darkGray,
                            child: group
                                ? Icon(Icons.group,
                                    size: 18, color: colors.dirtyWhite)
                                : Text(title.isNotEmpty
                                    ? title[0].toUpperCase()
                                    : '?'),
                          ),
                          title: Text(title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: group
                              ? Text(
                                  '${_others(channel, widget.selfId).length + 1} members',
                                  style: theme.textTheme.bodySmall)
                              : null,
                          onTap: () => widget.onOpen(channel),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _DmConversation extends ConsumerStatefulWidget {
  const _DmConversation({
    required this.channel,
    required this.selfId,
    required this.onBack,
  });

  final AccordChannel channel;
  final String? selfId;
  final VoidCallback onBack;

  @override
  ConsumerState<_DmConversation> createState() => _DmConversationState();
}

class _DmConversationState extends ConsumerState<_DmConversation> {
  final _input = TextEditingController();
  List<AccordMessage>? _messages;
  late AccordChannel _channel = widget.channel;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  AccordClient? get _client => ref.read(accordAuthProvider
      .select((s) => s is AccordAuthLoggedIn ? s.client : null));

  bool get _isGroupChannel => _isGroup(_channel, widget.selfId);

  bool get _isOwner =>
      _channel.ownerId != null && _channel.ownerId == widget.selfId;

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    final result =
        await client.messages.list(_channel.id, query: {'limit': 50});
    if (!mounted) return;
    final data = result.data;
    setState(() {
      _messages = data is List
          ? data.whereType<AccordMessage>().toList().reversed.toList()
          : <AccordMessage>[];
    });
  }

  /// Refetches the channel so the recipient list reflects add/remove changes.
  Future<void> _refreshChannel() async {
    final client = _client;
    if (client == null) return;
    final result = await client.channels.fetch(_channel.id);
    if (!mounted) return;
    final data = result.data;
    if (result.ok && data is AccordChannel) {
      setState(() => _channel = data);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final client = _client;
    if (client == null) return;
    setState(() => _sending = true);
    final result =
        await client.messages.create(_channel.id, {'content': text});
    if (!mounted) return;
    setState(() => _sending = false);
    final message = result.data;
    if (result.ok && message is AccordMessage) {
      _input.clear();
      setState(() => _messages = [...?_messages, message]);
    }
  }

  Future<void> _addMember() async {
    final user = await showDialog<AccordUser>(
      context: context,
      builder: (_) => _PickUserDialog(
        title: 'Add to group',
        excludeIds: {
          if (widget.selfId != null) widget.selfId!,
          ..._others(_channel, widget.selfId).map((u) => u.id),
        },
      ),
    );
    if (user == null) return;
    final client = _client;
    if (client == null) return;
    final result = await client.channels.addRecipient(_channel.id, user.id);
    if (!mounted) return;
    if (result.ok) {
      await _refreshChannel();
    } else {
      _snack('Failed to add member');
    }
  }

  Future<void> _removeMember(AccordUser user) async {
    final client = _client;
    if (client == null) return;
    final ok = await _confirm(
        'Remove member', 'Remove ${_userName(user)} from this group?', 'Remove');
    if (ok != true) return;
    final result =
        await client.channels.removeRecipient(_channel.id, user.id);
    if (!mounted) return;
    if (result.ok) {
      await _refreshChannel();
    } else {
      _snack('Failed to remove member');
    }
  }

  Future<void> _rename() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameGroupDialog(initial: _channel.name ?? ''),
    );
    if (name == null) return;
    final client = _client;
    if (client == null) return;
    final result =
        await client.channels.update(_channel.id, {'name': name.trim()});
    if (!mounted) return;
    final data = result.data;
    if (result.ok && data is AccordChannel) {
      setState(() => _channel = data);
    } else if (result.ok) {
      await _refreshChannel();
    } else {
      _snack('Failed to rename group');
    }
  }

  Future<void> _leave() async {
    final selfId = widget.selfId;
    final client = _client;
    if (client == null || selfId == null) return;
    final ok = await _confirm(
        'Leave group', 'Leave this group? You can be re-added later.', 'Leave');
    if (ok != true) return;
    final result = await client.channels.removeRecipient(_channel.id, selfId);
    if (!mounted) return;
    if (result.ok) {
      widget.onBack();
    } else {
      _snack('Failed to leave group');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool?> _confirm(String title, String message, String action) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  void _showMembers() {
    showDialog<void>(
      context: context,
      builder: (_) => _GroupMembersDialog(
        members: _others(_channel, widget.selfId),
        canRemove: _isOwner,
        onRemove: (u) {
          Navigator.of(context).pop();
          _removeMember(u);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final messages = _messages;
    final group = _isGroupChannel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: widget.onBack,
                icon: Icon(Icons.arrow_back, size: 20, color: colors.dirtyWhite),
              ),
              if (group)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: colors.darkGray,
                    child:
                        Icon(Icons.group, size: 16, color: colors.dirtyWhite),
                  ),
                ),
              Expanded(
                child: Text(_channelTitle(_channel, widget.selfId),
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis),
              ),
              if (group)
                PopupMenuButton<String>(
                  tooltip: 'Group options',
                  icon: Icon(Icons.more_vert, size: 20, color: colors.gray),
                  onSelected: (value) {
                    switch (value) {
                      case 'members':
                        _showMembers();
                      case 'add':
                        _addMember();
                      case 'rename':
                        _rename();
                      case 'leave':
                        _leave();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                        value: 'members', child: Text('View members')),
                    const PopupMenuItem(
                        value: 'add', child: Text('Add member')),
                    const PopupMenuItem(
                        value: 'rename', child: Text('Rename group')),
                    PopupMenuItem(
                      value: 'leave',
                      child:
                          Text('Leave group', style: TextStyle(color: colors.red)),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: messages == null
              ? const Center(child: CircularProgressIndicator())
              : messages.isEmpty
                  ? Center(
                      child: Text('No messages yet',
                          style: theme.textTheme.bodySmall))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final m = messages[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: AccordMessageContent(content: m.content),
                        );
                      },
                    ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  enabled: !_sending,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Message',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              IconButton(
                onPressed: _sending ? null : _send,
                icon: Icon(Icons.send, size: 20, color: colors.dirtyWhite),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FriendsTab extends ConsumerStatefulWidget {
  const _FriendsTab();

  @override
  ConsumerState<_FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends ConsumerState<_FriendsTab> {
  List<AccordRelationship>? _relationships;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  AccordClient? get _client => ref.read(accordAuthProvider
      .select((s) => s is AccordAuthLoggedIn ? s.client : null));

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    final result = await client.users.listRelationships();
    if (!mounted) return;
    final data = result.data;
    setState(() {
      _relationships = data is List
          ? data.whereType<AccordRelationship>().toList()
          : <AccordRelationship>[];
    });
  }

  Future<void> _accept(String userId) async {
    final client = _client;
    if (client == null) return;
    setState(() => _busy = true);
    final result = await client.users.putRelationship(userId, {'type': _Rel.friend});
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.ok) await _load();
  }

  Future<void> _remove(String userId) async {
    final client = _client;
    if (client == null) return;
    setState(() => _busy = true);
    final result = await client.users.deleteRelationship(userId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.ok) await _load();
  }

  Future<void> _addFriend() async {
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddFriendDialog(),
    );
    if (added == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final all = _relationships;
    if (all == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final incoming = all.where((r) => r.type == _Rel.pendingIn).toList();
    final outgoing = all.where((r) => r.type == _Rel.pendingOut).toList();
    final friends = all.where((r) => r.type == _Rel.friend).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _busy ? null : _addFriend,
              icon: const Icon(Icons.person_add, size: 18),
              label: const Text('Add friend'),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              if (incoming.isNotEmpty)
                _SectionLabel('Incoming requests', colors: colors),
              for (final r in incoming)
                _FriendRow(
                  name: _userName(r.user),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Accept',
                        onPressed: _busy || r.user == null
                            ? null
                            : () => _accept(r.user!.id),
                        icon: Icon(Icons.check, color: colors.green, size: 20),
                      ),
                      IconButton(
                        tooltip: 'Decline',
                        onPressed: _busy || r.user == null
                            ? null
                            : () => _remove(r.user!.id),
                        icon: Icon(Icons.close, color: colors.red, size: 20),
                      ),
                    ],
                  ),
                ),
              if (outgoing.isNotEmpty)
                _SectionLabel('Outgoing requests', colors: colors),
              for (final r in outgoing)
                _FriendRow(
                  name: _userName(r.user),
                  trailing: TextButton(
                    onPressed: _busy || r.user == null
                        ? null
                        : () => _remove(r.user!.id),
                    child: const Text('Cancel'),
                  ),
                ),
              if (friends.isNotEmpty)
                _SectionLabel('Friends', colors: colors),
              for (final r in friends)
                _FriendRow(
                  name: _userName(r.user),
                  trailing: IconButton(
                    tooltip: 'Remove friend',
                    onPressed: _busy || r.user == null
                        ? null
                        : () => _remove(r.user!.id),
                    icon: Icon(Icons.person_remove,
                        color: colors.gray, size: 20),
                  ),
                ),
              if (incoming.isEmpty && outgoing.isEmpty && friends.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                      child: Text('No friends yet',
                          style: theme.textTheme.bodyMedium)),
                ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_error!,
                style:
                    theme.textTheme.bodySmall!.copyWith(color: colors.red)),
          ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {required this.colors});

  final String label;
  final BonfireThemeExtension colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Text(label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall!.copyWith(
              color: colors.gray, fontWeight: FontWeight.bold)),
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({required this.name, required this.trailing});

  final String name;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: colors.darkGray,
        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing,
    );
  }
}

class _AddFriendDialog extends ConsumerStatefulWidget {
  const _AddFriendDialog();

  @override
  ConsumerState<_AddFriendDialog> createState() => _AddFriendDialogState();
}

class _AddFriendDialogState extends ConsumerState<_AddFriendDialog> {
  final _query = TextEditingController();
  List<AccordUser>? _results;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  AccordClient? get _client => ref.read(accordAuthProvider
      .select((s) => s is AccordAuthLoggedIn ? s.client : null));

  Future<void> _search() async {
    final client = _client;
    final query = _query.text.trim();
    if (client == null || query.isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final result = await client.users.searchUsers(query);
    if (!mounted) return;
    final data = result.data;
    setState(() {
      _busy = false;
      _results =
          data is List ? data.whereType<AccordUser>().toList() : <AccordUser>[];
    });
  }

  Future<void> _request(AccordUser user) async {
    final client = _client;
    if (client == null) return;
    setState(() => _busy = true);
    final result = await client.users.putRelationship(user.id, {'type': _Rel.friend});
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = result.ok
          ? 'Friend request sent to ${_userName(user)}'
          : 'Failed to send request';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final results = _results;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add friend', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _query,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Search by username',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _search,
                    child: const Text('Search'),
                  ),
                ],
              ),
              if (_message != null) ...[
                const SizedBox(height: 8),
                Text(_message!,
                    style: theme.textTheme.bodySmall!
                        .copyWith(color: colors.green)),
              ],
              const SizedBox(height: 8),
              Flexible(
                child: results == null
                    ? const SizedBox.shrink()
                    : results.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('No users found',
                                style: theme.textTheme.bodySmall),
                          )
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              for (final user in results)
                                ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 16,
                                    backgroundColor: colors.darkGray,
                                    child: Text(_userName(user)[0].toUpperCase()),
                                  ),
                                  title: Text(_userName(user),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  trailing: IconButton(
                                    tooltip: 'Send request',
                                    onPressed:
                                        _busy ? null : () => _request(user),
                                    icon: Icon(Icons.person_add,
                                        size: 18, color: colors.primary),
                                  ),
                                ),
                            ],
                          ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Multi-select dialog to start a group DM. Searches users, lets the caller pick
/// several recipients, then POSTs `{recipients: [...]}` to create the channel.
class _CreateGroupDialog extends ConsumerStatefulWidget {
  const _CreateGroupDialog();

  @override
  ConsumerState<_CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends ConsumerState<_CreateGroupDialog> {
  final _query = TextEditingController();
  final _name = TextEditingController();
  final _selected = <String, AccordUser>{};
  List<AccordUser>? _results;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _query.dispose();
    _name.dispose();
    super.dispose();
  }

  AccordClient? get _client => ref.read(accordAuthProvider
      .select((s) => s is AccordAuthLoggedIn ? s.client : null));

  Future<void> _search() async {
    final client = _client;
    final query = _query.text.trim();
    if (client == null || query.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await client.users.searchUsers(query);
    if (!mounted) return;
    final data = result.data;
    setState(() {
      _busy = false;
      _results =
          data is List ? data.whereType<AccordUser>().toList() : <AccordUser>[];
    });
  }

  Future<void> _create() async {
    final client = _client;
    if (client == null || _selected.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final payload = <String, dynamic>{'recipients': _selected.keys.toList()};
    final name = _name.text.trim();
    if (name.isNotEmpty) payload['name'] = name;
    final result = await client.users.createDm(payload);
    if (!mounted) return;
    final data = result.data;
    if (result.ok && data is AccordChannel) {
      Navigator.of(context).pop(data);
    } else {
      setState(() {
        _busy = false;
        _error = 'Failed to create group';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final results = _results;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('New group', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                enabled: !_busy,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Group name (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _query,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Search users to add',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _search,
                    child: const Text('Search'),
                  ),
                ],
              ),
              if (_selected.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final user in _selected.values)
                      InputChip(
                        label: Text(_userName(user)),
                        onDeleted: _busy
                            ? null
                            : () => setState(() => _selected.remove(user.id)),
                      ),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: theme.textTheme.bodySmall!
                        .copyWith(color: colors.red)),
              ],
              const SizedBox(height: 8),
              Flexible(
                child: results == null
                    ? const SizedBox.shrink()
                    : results.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('No users found',
                                style: theme.textTheme.bodySmall),
                          )
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              for (final user in results)
                                CheckboxListTile(
                                  dense: true,
                                  value: _selected.containsKey(user.id),
                                  onChanged: _busy
                                      ? null
                                      : (checked) => setState(() {
                                            if (checked == true) {
                                              _selected[user.id] = user;
                                            } else {
                                              _selected.remove(user.id);
                                            }
                                          }),
                                  title: Text(_userName(user),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ),
                            ],
                          ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy || _selected.isEmpty ? null : _create,
                    child: Text('Create (${_selected.length})'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Single-user search/pick dialog. Returns the chosen [AccordUser]. Used to add
/// a member to an existing group; [excludeIds] hides current participants.
class _PickUserDialog extends ConsumerStatefulWidget {
  const _PickUserDialog({required this.title, required this.excludeIds});

  final String title;
  final Set<String> excludeIds;

  @override
  ConsumerState<_PickUserDialog> createState() => _PickUserDialogState();
}

class _PickUserDialogState extends ConsumerState<_PickUserDialog> {
  final _query = TextEditingController();
  List<AccordUser>? _results;
  bool _busy = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  AccordClient? get _client => ref.read(accordAuthProvider
      .select((s) => s is AccordAuthLoggedIn ? s.client : null));

  Future<void> _search() async {
    final client = _client;
    final query = _query.text.trim();
    if (client == null || query.isEmpty) return;
    setState(() => _busy = true);
    final result = await client.users.searchUsers(query);
    if (!mounted) return;
    final data = result.data;
    setState(() {
      _busy = false;
      _results = data is List
          ? data
              .whereType<AccordUser>()
              .where((u) => !widget.excludeIds.contains(u.id))
              .toList()
          : <AccordUser>[];
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final results = _results;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _query,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Search by username',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _search,
                    child: const Text('Search'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: results == null
                    ? const SizedBox.shrink()
                    : results.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('No users found',
                                style: theme.textTheme.bodySmall),
                          )
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              for (final user in results)
                                ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 16,
                                    backgroundColor: colors.darkGray,
                                    child:
                                        Text(_userName(user)[0].toUpperCase()),
                                  ),
                                  title: Text(_userName(user),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  onTap: () =>
                                      Navigator.of(context).pop(user),
                                ),
                            ],
                          ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Prompts for a new group name. Returns the trimmed name, or null on cancel.
class _RenameGroupDialog extends StatefulWidget {
  const _RenameGroupDialog({required this.initial});

  final String initial;

  @override
  State<_RenameGroupDialog> createState() => _RenameGroupDialogState();
}

class _RenameGroupDialogState extends State<_RenameGroupDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename group'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          isDense: true,
          labelText: 'Group name',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) =>
            Navigator.of(context).pop(_controller.text.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Lists the group's participants with an optional remove action (owner only).
class _GroupMembersDialog extends StatelessWidget {
  const _GroupMembersDialog({
    required this.members,
    required this.canRemove,
    required this.onRemove,
  });

  final List<AccordUser> members;
  final bool canRemove;
  final void Function(AccordUser) onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Members (${members.length})',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Flexible(
                child: members.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('No other members',
                            style: theme.textTheme.bodySmall),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final user in members)
                            ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: colors.darkGray,
                                child: Text(_userName(user)[0].toUpperCase()),
                              ),
                              title: Text(_userName(user),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              trailing: canRemove
                                  ? IconButton(
                                      tooltip: 'Remove',
                                      onPressed: () => onRemove(user),
                                      icon: Icon(Icons.person_remove,
                                          size: 20, color: colors.red),
                                    )
                                  : null,
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
