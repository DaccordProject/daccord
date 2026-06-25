part of 'accord_direct_messages.dart';

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

  AccordClient? get _client => ref.accordClient;

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
      _results = data is List
          ? data.whereType<AccordUser>().toList()
          : <AccordUser>[];
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
    final results = _results;
    return Dialog(
      child: ConstrainedBox(
        constraints: dialogConstraints(context, maxWidth: 460, maxHeight: 600),
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
                InlineError(_error!, centered: false),
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
                              title: Text(
                                _userName(user),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
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

  AccordClient? get _client => ref.accordClient;

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
        constraints: dialogConstraints(context, maxWidth: 440, maxHeight: 520),
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
                                child: Text(accordInitial(_userName(user))),
                              ),
                              title: Text(
                                _userName(user),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => Navigator.of(context).pop(user),
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
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

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
        onSubmitted: (_) => Navigator.of(context).pop(_controller.text.trim()),
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
        constraints: dialogConstraints(context, maxWidth: 420, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Members (${members.length})',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Flexible(
                child: members.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No other members',
                          style: theme.textTheme.bodySmall,
                        ),
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
                                child: Text(accordInitial(_userName(user))),
                              ),
                              title: Text(
                                _userName(user),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: canRemove
                                  ? IconButton(
                                      tooltip: 'Remove',
                                      onPressed: () => onRemove(user),
                                      icon: Icon(
                                        Icons.person_remove,
                                        size: 20,
                                        color: colors.red,
                                      ),
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
