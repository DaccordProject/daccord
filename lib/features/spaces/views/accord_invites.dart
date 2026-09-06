import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/responsive_dialog.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/self_loading_list.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
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

class _InvitesDialogState extends ConsumerState<_InvitesDialog>
    with SelfLoadingListState<AccordInvite, _InvitesDialog> {
  bool _creating = false;
  int _expirySeconds = 86400;
  int _maxUses = 0;
  bool _temporary = false;
  String _query = '';
  final Set<String> _selected = {};

  AccordClient? get _client => ref.accordClient;

  String? get _baseUrl => ref.read(
    accordAuthProvider.select(
      (s) => s is AccordAuthLoggedIn ? s.session.server.baseUrl : null,
    ),
  );

  @override
  bool get canLoad => _client != null;

  @override
  Future<(List<AccordInvite>? items, String? error)> fetchItems() async {
    final result = await _client!.invites.listSpace(widget.spaceId);
    final data = result.data;
    return (
      result.ok && data is List
          ? data.whereType<AccordInvite>().toList()
          : const <AccordInvite>[],
      result.ok ? null : 'Failed to load invites',
    );
  }

  Future<void> _create() async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _creating = true;
      error = null;
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
      await load();
      if (!mounted) return;
      setState(() => _creating = false);
    } else {
      setState(() {
        _creating = false;
        error = 'Failed to create invite';
      });
    }
  }

  Future<void> _revoke(AccordInvite invite) async {
    final client = _client;
    if (client == null) return;
    final result = await client.invites.delete(invite.code);
    if (!mounted) return;
    if (result.ok) {
      setState(
        () => items = items?.where((i) => i.code != invite.code).toList(),
      );
    } else {
      setState(() => error = 'Failed to revoke invite');
    }
  }

  /// Revokes every selected invite, then clears the selection.
  Future<void> _revokeSelected() async {
    final client = _client;
    if (client == null || _selected.isEmpty) return;
    final codes = _selected.toList();
    for (final code in codes) {
      final result = await client.invites.delete(code);
      if (result.ok) {
        items = items?.where((i) => i.code != code).toList();
      }
    }
    if (!mounted) return;
    setState(() => _selected.clear());
  }

  String _inviteLink(AccordInvite invite) {
    final base = _baseUrl;
    if (base == null) return invite.code;
    return '$base/invite/${invite.code}';
  }

  Future<void> _copy(AccordInvite invite) async {
    await Clipboard.setData(ClipboardData(text: _inviteLink(invite)));
    if (!mounted) return;
    showInfoSnack(context, 'Invite link copied');
  }

  String _usesLabel(AccordInvite invite) {
    final max = invite.maxUses;
    final maxInt = asInt(max);
    if (maxInt <= 0) return '${invite.uses} uses';
    return '${invite.uses}/$maxInt uses';
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final invites = items;
    return Dialog(
      child: ConstrainedBox(
        constraints: dialogConstraints(context, maxWidth: 480, maxHeight: 600),
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
                            value: p.seconds,
                            child: Text(p.label),
                          ),
                      ],
                      onChanged: _creating
                          ? null
                          : (v) => setState(() => _expirySeconds = v ?? 86400),
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
                      subtitle: Text(
                        'Kicked on disconnect unless given a role',
                        style: theme.textTheme.bodySmall,
                      ),
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
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  error!,
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            const Divider(height: 1),
            if (invites != null && invites.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (v) =>
                            setState(() => _query = v.trim().toLowerCase()),
                        decoration: InputDecoration(
                          isDense: true,
                          prefixIcon: Icon(
                            Icons.search,
                            size: 18,
                            color: colors.gray,
                          ),
                          hintText: 'Search invites',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    if (_selected.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _revokeSelected,
                        icon: Icon(
                          Icons.delete_sweep_outlined,
                          size: 18,
                          color: theme.colorScheme.error,
                        ),
                        label: Text(
                          'Revoke ${_selected.length}',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            Flexible(
              child: invites == null
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: LoadingView(),
                    )
                  : invites.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'No active invites',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    )
                  : Builder(
                      builder: (context) {
                        final filtered = _query.isEmpty
                            ? invites
                            : invites
                                  .where(
                                    (i) =>
                                        i.code.toLowerCase().contains(_query),
                                  )
                                  .toList();
                        if (filtered.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(32),
                            child: Center(
                              child: Text(
                                'No matches',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          );
                        }
                        return ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.all(8),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final invite = filtered[index];
                            final selected = _selected.contains(invite.code);
                            return ListTile(
                              leading: Checkbox(
                                value: selected,
                                onChanged: (v) => setState(() {
                                  if (v ?? false) {
                                    _selected.add(invite.code);
                                  } else {
                                    _selected.remove(invite.code);
                                  }
                                }),
                              ),
                              title: Text(
                                invite.code,
                                style: theme.textTheme.titleSmall,
                              ),
                              subtitle: Text(
                                _usesLabel(invite),
                                style: theme.textTheme.bodySmall,
                              ),
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
                                    icon: Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
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
