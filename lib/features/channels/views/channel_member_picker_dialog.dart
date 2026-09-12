import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

/// Search-and-pick dialog used to add a new member permission overwrite from
/// [showChannelPermissionsDialog]. Pops the picked member's user ID, or `null`
/// if dismissed.
class ChannelMemberPickerDialog extends StatefulWidget {
  const ChannelMemberPickerDialog({super.key, required this.members});

  final List<AccordMember> members;

  @override
  State<ChannelMemberPickerDialog> createState() =>
      _ChannelMemberPickerDialogState();
}

class _ChannelMemberPickerDialogState
    extends State<ChannelMemberPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final q = _query.trim().toLowerCase();
    final matches = widget.members
        .where(
          (m) => q.isEmpty || accordMemberName(m).toLowerCase().contains(q),
        )
        .sortedBy((m) => accordMemberName(m).toLowerCase());

    return Dialog(
      backgroundColor: colors.foreground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320, maxHeight: 420),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: 'Search members',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Flexible(
              child: matches.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No members',
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      children: [
                        for (final m in matches)
                          ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.person_outline,
                              color: colors.gray,
                            ),
                            title: Text(accordMemberName(m)),
                            onTap: () => Navigator.of(context).pop(m.userId),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
