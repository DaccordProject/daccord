part of 'accord_direct_messages.dart';

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

  AccordClient? get _client => ref.read(
    accordAuthProvider.select((s) => s is AccordAuthLoggedIn ? s.client : null),
  );

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
    final result = await client.users.putRelationship(userId, {
      'type': _Rel.friend,
    });
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

  Future<void> _block(String userId) async {
    final client = _client;
    if (client == null) return;
    setState(() => _busy = true);
    final result = await client.users.putRelationship(userId, {
      'type': _Rel.blocked,
    });
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
    final blocked = all.where((r) => r.type == _Rel.blocked).toList();

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
              if (friends.isNotEmpty) _SectionLabel('Friends', colors: colors),
              for (final r in friends)
                _FriendRow(
                  name: _userName(r.user),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Block',
                        onPressed: _busy || r.user == null
                            ? null
                            : () => _block(r.user!.id),
                        icon: Icon(Icons.block, color: colors.gray, size: 20),
                      ),
                      IconButton(
                        tooltip: 'Remove friend',
                        onPressed: _busy || r.user == null
                            ? null
                            : () => _remove(r.user!.id),
                        icon: Icon(
                          Icons.person_remove,
                          color: colors.gray,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              if (blocked.isNotEmpty) _SectionLabel('Blocked', colors: colors),
              for (final r in blocked)
                _FriendRow(
                  name: _userName(r.user),
                  trailing: TextButton(
                    onPressed: _busy || r.user == null
                        ? null
                        : () => _remove(r.user!.id),
                    child: const Text('Unblock'),
                  ),
                ),
              if (incoming.isEmpty &&
                  outgoing.isEmpty &&
                  friends.isEmpty &&
                  blocked.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No friends yet',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              _error!,
              style: theme.textTheme.bodySmall!.copyWith(color: colors.red),
            ),
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
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall!.copyWith(
          color: colors.gray,
          fontWeight: FontWeight.bold,
        ),
      ),
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

  AccordClient? get _client => ref.read(
    accordAuthProvider.select((s) => s is AccordAuthLoggedIn ? s.client : null),
  );

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
      _results = data is List
          ? data.whereType<AccordUser>().toList()
          : <AccordUser>[];
    });
  }

  Future<void> _request(AccordUser user) async {
    final client = _client;
    if (client == null) return;
    setState(() => _busy = true);
    final result = await client.users.putRelationship(user.id, {
      'type': _Rel.friend,
    });
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
                Text(
                  _message!,
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: colors.green,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Flexible(
                child: results == null
                    ? const SizedBox.shrink()
                    : results.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No users found',
                          style: theme.textTheme.bodySmall,
                        ),
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
                              title: Text(
                                _userName(user),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: IconButton(
                                tooltip: 'Send request',
                                onPressed: _busy ? null : () => _request(user),
                                icon: Icon(
                                  Icons.person_add,
                                  size: 18,
                                  color: colors.primary,
                                ),
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
