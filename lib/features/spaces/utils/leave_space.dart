import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Confirms, then leaves [space] on the [serverKey] connection — also deleting
/// the user's messages and data there when [deleteData] — and drops it from
/// the rail and active space lists. [onBusy] brackets the leave request.
/// Owner-guarded by callers: an owner must transfer ownership first.
Future<void> leaveSpace(
  BuildContext context,
  WidgetRef ref,
  AccordSpace space,
  String serverKey, {
  bool deleteData = false,
  ValueChanged<bool>? onBusy,
}) async {
  final confirmed = await showConfirmDialog(
    context,
    title: deleteData ? 'Leave & delete data' : "Leave '${space.name}'?",
    message: deleteData
        ? "This will permanently leave '${space.name}' and delete all your "
              'messages, reactions, and data from this server. Your account '
              'stays active. This cannot be undone.'
        : 'You will lose access to this server until you rejoin with an '
              'invite. Your messages stay on the server.',
    confirmLabel: deleteData ? 'Leave & delete' : 'Leave',
    danger: true,
  );
  if (confirmed != true || !context.mounted) return;

  final client = ref.read(accordAuthProvider.notifier).clientForKey(serverKey);
  if (client == null) return;
  // The route can close while leaving; cache updates belong to its app scope.
  final container = ProviderScope.containerOf(context, listen: false);
  onBusy?.call(true);
  final result = await client.members.leaveMe(space.id, deleteData: deleteData);
  if (context.mounted) onBusy?.call(false);
  if (!result.ok) {
    if (context.mounted) {
      showErrorSnack(context, result, prefix: 'Failed to leave');
    }
    return;
  }
  container
      .read(connectionsControllerProvider.notifier)
      .removeSpace(serverKey, space.id);
  if (container.read(connectionsControllerProvider).activeKey == serverKey) {
    container.read(spacesControllerProvider.notifier).removeSpace(space.id);
  }
  if (!context.mounted) return;
  showInfoSnack(
    context,
    deleteData
        ? "Left '${space.name}' and deleted your data"
        : "Left '${space.name}'",
  );
}
