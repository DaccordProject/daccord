import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:flutter/material.dart';

/// Confirmation dialog shown before logging out. Returns `true` only when the
/// user explicitly confirms.
Future<bool> confirmLogout(BuildContext context) async {
  final confirmed = await showConfirmDialog(
    context,
    title: 'Log out?',
    message: "You'll need to sign in again to use this account.",
    confirmLabel: 'Log out',
    danger: true,
  );
  return confirmed ?? false;
}
