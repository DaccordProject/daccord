import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/responsive_dialog.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens a dialog to transfer ownership of [spaceId] to another member. Only the
/// current owner should see this entry point. Requires a typed confirmation.
Future<void> showTransferOwnership(
  BuildContext context, {
  required String spaceId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _TransferOwnershipDialog(spaceId: spaceId),
  );
}

class _TransferOwnershipDialog extends ConsumerStatefulWidget {
  const _TransferOwnershipDialog({required this.spaceId});

  final String spaceId;

  @override
  ConsumerState<_TransferOwnershipDialog> createState() =>
      _TransferOwnershipDialogState();
}

class _TransferOwnershipDialogState
    extends ConsumerState<_TransferOwnershipDialog> {
  String? _selectedId;
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final client = ref.accordClient;
    final target = _selectedId;
    if (client == null || target == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await client.spaces.update(widget.spaceId, {
      'owner_id': target,
    });
    if (!mounted) return;
    final space = result.data;
    if (result.ok && space is AccordSpace) {
      ref.read(spacesControllerProvider.notifier).upsertSpace(space);
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _error = result.errorOr('Failed to transfer ownership');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final currentUserId = ref.watchUserId();
    final members = ref.watch(accordMembersControllerProvider(widget.spaceId));
    final candidates =
        (members?.values ?? const <AccordMember>[])
            .where((m) => m.userId != currentUserId)
            .toList()
          ..sort(
            (a, b) => accordMemberName(a, fallback: 'Unknown')
                .toLowerCase()
                .compareTo(
                  accordMemberName(b, fallback: 'Unknown').toLowerCase(),
                ),
          );
    final canSubmit =
        _selectedId != null &&
        _confirm.text.trim().toUpperCase() == 'TRANSFER' &&
        !_busy;

    return Dialog(
      child: ConstrainedBox(
        constraints: dialogConstraints(context, maxWidth: 440, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Transfer ownership', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'The new owner gains full control. You cannot undo this.',
                style: theme.textTheme.bodySmall!.copyWith(color: colors.red),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: candidates.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No other members to transfer to.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final m in candidates)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: Icon(
                                _selectedId == m.userId
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                                size: 18,
                                color: _selectedId == m.userId
                                    ? colors.primary
                                    : colors.gray,
                              ),
                              title: Text(
                                accordMemberName(m, fallback: 'Unknown'),
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: _busy
                                  ? null
                                  : () =>
                                        setState(() => _selectedId = m.userId),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirm,
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Type TRANSFER to confirm',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                InlineError(_error!, centered: false),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).maybePop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: canSubmit ? _submit : null,
                    style: FilledButton.styleFrom(backgroundColor: colors.red),
                    child: const Text('Transfer'),
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
