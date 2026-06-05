import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/user/views/accord_account_settings.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The statuses a user can set for themselves.
const _statusOptions = <({String value, String label, IconData icon})>[
  (value: 'online', label: 'Online', icon: Icons.circle),
  (value: 'idle', label: 'Idle', icon: Icons.nightlight_round),
  (value: 'dnd', label: 'Do Not Disturb', icon: Icons.remove_circle),
  (value: 'invisible', label: 'Invisible', icon: Icons.circle_outlined),
];

/// A presence dot the user can tap to change their own status. Sends the new
/// status over the gateway and optimistically updates the local presence cache
/// so the dot reflects the choice immediately.
class SelfStatusButton extends ConsumerWidget {
  const SelfStatusButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final userId = ref.watch(accordAuthProvider
        .select((s) => s is AccordAuthLoggedIn ? s.session.userId : null));
    final status = ref.watch(presenceControllerProvider
        .select((p) => userId == null ? 'offline' : accordPresenceStatus(p, userId)));
    final dotColor = accordPresenceColor(status) ?? colors.gray;

    return PopupMenuButton<String>(
      tooltip: 'Set status',
      onSelected: (value) {
        if (value == _accountValue) {
          showAccordAccountSettings(context);
        } else {
          _setStatus(ref, userId, value);
        }
      },
      itemBuilder: (context) => [
        for (final option in _statusOptions)
          PopupMenuItem(
            value: option.value,
            child: Row(
              children: [
                Icon(option.icon,
                    size: 14,
                    color: accordPresenceColor(option.value) ?? colors.gray),
                const SizedBox(width: 10),
                Text(option.label),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _accountValue,
          child: Row(
            children: [
              Icon(Icons.manage_accounts, size: 16, color: colors.gray),
              const SizedBox(width: 10),
              const Text('Account settings'),
            ],
          ),
        ),
      ],
      icon: Icon(Icons.circle, size: 16, color: dotColor),
    );
  }

  static const String _accountValue = '__account__';

  void _setStatus(WidgetRef ref, String? userId, String status) {
    final client = ref.read(accordAuthProvider
        .select((s) => s is AccordAuthLoggedIn ? s.client : null));
    if (client == null) return;
    client.gateway.updatePresence(status);
    if (userId != null) {
      ref.read(presenceControllerProvider.notifier).upsert(
            AccordPresence(userId: userId, status: status),
          );
    }
  }
}
