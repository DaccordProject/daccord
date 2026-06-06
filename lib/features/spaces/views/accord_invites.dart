import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the invite-management dialog for [spaceId]: lists active invites,
/// creates new ones, and revokes existing ones.
Future<void> showAccordInvites(
  BuildContext context, {
  required String spaceId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _InvitesDialog(spaceId: spaceId),
  );
}

/// Preset invite expirations, mapped to `max_age` seconds (0 = never).
const _expiryPresets = <({String label, int seconds})>[
  (label: '30 minutes', seconds: 1800),
  (label: '1 hour', seconds: 3600),
  (label: '1 day', seconds: 86400),
  (label: '7 days', seconds: 604800),
  (label: 'Never', seconds: 0),
];

/// Preset max-use limits, mapped to the `max_uses` count (0 = unlimited).
const _maxUsesPresets = <({String label, int uses})>[
  (label: 'No limit', uses: 0),
  (label: '1 use', uses: 1),
  (label: '5 uses', uses: 5),
  (label: '10 uses', uses: 10),
  (label: '25 uses', uses: 25),
  (label: '50 uses', uses: 50),
  (label: '100 uses', uses: 100),
];

class _InvitesDialog extends ConsumerStatefulWidget {
  const _InvitesDialog({required this.spaceId});

  final String spaceId;

  @override
  ConsumerState<_InvitesDialog> createState() => _InvitesDialogState();
}

class _InvitesDialogState extends ConsumerState<_InvitesDialog> {
  List<AccordInvite>? _invites;
  bool _creating = false;
  String? _error;
  int _expirySeconds = 86400;
  int _maxUses = 0;
  bool _temporary = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  AccordClient? get _client => ref.read(accordAuthProvider
      .select((s) => s is AccordAuthLoggedIn ? s.client : null));

  String? get _baseUrl => ref.read(accordAuthProvider.select(
      (s) => s is AccordAuthLoggedIn ? s.session.server.baseUrl : null));

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    final result = await client.invites.listSpace(widget.spaceId);
    if (!mounted) return;
    final data = result.data;
    setState(() {
      _invites = result.ok && data is List
          ? data.whereType<AccordInvite>().toList()
          : const [];
      if (!result.ok) _error = 'Failed to load invites';
    });
  }

  Future<void> _create() async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    final result = await client.invites.createSpace(
      widget.spaceId,
      data: {
        'max_age': _expirySeconds,
        'max_uses': _maxUses,
        'temporary': _temporary,
      },
    );
    if (!mounted) return;
    if (result.ok) {
      await _load();
      if (!mounted) return;
      setState(() => _creating = false);
    } else {
      setState(() {
        _creating = false;
        _error = 'Failed to create invite';
      });
    }
  }

  Future<void> _revoke(AccordInvite invite) async {
    final client = _client;
    if (client == null) return;
    final result = await client.invites.delete(invite.code);
    if (!mounted) return;
    if (result.ok) {
      setState(() => _invites =
          _invites?.where((i) => i.code != invite.code).toList());
    } else {
      setState(() => _error = 'Failed to revoke invite');
    }
  }

  String _inviteLink(AccordInvite invite) {
    final base = _baseUrl;
    if (base == null) return invite.code;
    return '$base/invite/${invite.code}';
  }

  Future<void> _copy(AccordInvite invite) async {
    await Clipboard.setData(ClipboardData(text: _inviteLink(invite)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite link copied')),
    );
  }

  String _usesLabel(AccordInvite invite) {
    final max = invite.maxUses;
    final maxInt = max is int ? max : int.tryParse('$max') ?? 0;
    if (maxInt <= 0) return '${invite.uses} uses';
    return '${invite.uses}/$maxInt uses';
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final invites = _invites;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.person_add, size: 18, color: colors.dirtyWhite),
                  const SizedBox(width: 8),
                  Text('Invite people', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _expirySeconds,
                      decoration: const InputDecoration(
                        labelText: 'Expire after',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final p in _expiryPresets)
                          DropdownMenuItem(
                              value: p.seconds, child: Text(p.label)),
                      ],
                      onChanged: _creating
                          ? null
                          : (v) =>
                              setState(() => _expirySeconds = v ?? 86400),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _maxUses,
                      decoration: const InputDecoration(
                        labelText: 'Max uses',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final p in _maxUsesPresets)
                          DropdownMenuItem(value: p.uses, child: Text(p.label)),
                      ],
                      onChanged: _creating
                          ? null
                          : (v) => setState(() => _maxUses = v ?? 0),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: CheckboxListTile(
                      value: _temporary,
                      onChanged: _creating
                          ? null
                          : (v) => setState(() => _temporary = v ?? false),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      title: const Text('Temporary membership'),
                      subtitle: Text('Kicked on disconnect unless given a role',
                          style: theme.textTheme.bodySmall),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _creating ? null : _create,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Create'),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_error!,
                    style: theme.textTheme.bodySmall!
                        .copyWith(color: theme.colorScheme.error)),
              ),
            const Divider(height: 1),
            Flexible(
              child: invites == null
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : invites.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(
                            child: Text('No active invites',
                                style: theme.textTheme.bodyMedium),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.all(8),
                          itemCount: invites.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final invite = invites[index];
                            return ListTile(
                              title: Text(invite.code,
                                  style: theme.textTheme.titleSmall),
                              subtitle: Text(_usesLabel(invite),
                                  style: theme.textTheme.bodySmall),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Copy link',
                                    onPressed: () => _copy(invite),
                                    icon: const Icon(Icons.copy, size: 18),
                                  ),
                                  IconButton(
                                    tooltip: 'Revoke',
                                    onPressed: () => _revoke(invite),
                                    icon: Icon(Icons.delete_outline,
                                        size: 18,
                                        color: theme.colorScheme.error),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
