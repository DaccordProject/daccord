part of 'accord_direct_messages.dart';

/// Multi-select dialog to start a group DM. Searches users, lets the caller pick
/// several recipients, then POSTs `{recipients: [...]}` to create the channel.
class _CreateGroupDialog extends ConsumerStatefulWidget {
  const _CreateGroupDialog();

  @override
  ConsumerState<_CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends ConsumerState<_CreateGroupDialog> {
  final _name = TextEditingController();
  final _selected = <String, AccordUser>{};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  AccordClient? get _client => ref.accordClient;

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
              Flexible(
                child: _UserSearchList(
                  hintText: 'Search users to add',
                  busy: _busy,
                  onBusyChanged: (busy) => setState(() {
                    _busy = busy;
                    if (busy) _error = null;
                  }),
                  belowSearch: [
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
                                  : () => setState(
                                      () => _selected.remove(user.id),
                                    ),
                            ),
                        ],
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      InlineError(_error!, centered: false),
                    ],
                  ],
                  tileBuilder: (user) => CheckboxListTile(
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
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              Flexible(
                child: _UserSearchList(
                  hintText: 'Search by username',
                  busy: _busy,
                  onBusyChanged: (busy) => setState(() => _busy = busy),
                  excludeIds: widget.excludeIds,
                  tileBuilder: (user) => ListTile(
                    dense: true,
                    leading: UserAvatar(_userName(user)),
                    title: Text(
                      _userName(user),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.of(context).pop(user),
                  ),
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
                              leading: UserAvatar(_userName(user)),
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
