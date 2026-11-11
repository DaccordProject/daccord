import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

PrivateChatEncryption? _encryptionFromState(AccordAuthState state) =>
    state is AccordAuthLoggedIn ? state.client.encryption : null;

/// The active account's private-chat encryption, or null for guests and while
/// signed out. Rebuilds dependents when the account switches.
final privateChatEncryptionProvider = Provider<PrivateChatEncryption?>(
  (ref) => ref.watch(accordAuthProvider.select(_encryptionFromState)),
);

/// Whether this device can read and send encrypted private chats yet. Pending
/// means another device must approve it (or a backup must be imported).
final privateChatSetupProvider = StreamProvider<PrivateChatSetup>((ref) {
  final encryption = ref.watch(privateChatEncryptionProvider);
  if (encryption == null) return Stream.value(PrivateChatSetup.unknown);
  final controller = StreamController<PrivateChatSetup>();
  controller.add(encryption.setup);
  final subscription = encryption.setupChanges.listen(controller.add);
  ref.onDispose(() {
    subscription.cancel();
    controller.close();
  });
  return controller.stream;
});

/// Devices asking to join this account's encrypted chats, shown as approval
/// prompts on devices that are already set up. Fed by the gateway's
/// `encryption.device_pending` event and reconciled against the server's
/// device list whenever it reports a change.
final pendingDeviceRequestsProvider =
    NotifierProvider<PendingDeviceRequests, List<EncryptionDevice>>(
      PendingDeviceRequests.new,
    );

class PendingDeviceRequests extends Notifier<List<EncryptionDevice>> {
  final _dismissed = <String>{};

  @override
  List<EncryptionDevice> build() {
    _dismissed.clear();
    final encryption = ref.watch(privateChatEncryptionProvider);
    if (encryption == null) return const [];
    final subscriptions = [
      encryption.onDevicePending.listen(_add),
      encryption.onDevicesUpdate.listen((_) => unawaited(refresh())),
      encryption.setupChanges.listen((setup) {
        if (setup == PrivateChatSetup.active) unawaited(refresh());
      }),
    ];
    ref.onDispose(() {
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
    });
    // Requests made while this device was offline arrive with the list, not
    // as events.
    if (encryption.setup == PrivateChatSetup.active) unawaited(refresh());
    return const [];
  }

  void _add(EncryptionDevice device) {
    if (!ref.mounted ||
        device.current ||
        _dismissed.contains(device.deviceId)) {
      return;
    }
    if (ref.read(privateChatEncryptionProvider)?.setup !=
        PrivateChatSetup.active) {
      return;
    }
    state = [
      for (final existing in state)
        if (existing.deviceId != device.deviceId) existing,
      device,
    ];
  }

  /// Re-reads the device list: approved, declined or expired requests drop
  /// out, and requests this device missed while offline appear.
  Future<void> refresh() async {
    final encryption = ref.read(privateChatEncryptionProvider);
    if (encryption == null || encryption.setup != PrivateChatSetup.active) {
      return;
    }
    try {
      final devices = await encryption.listDevices();
      if (!ref.mounted ||
          ref.read(privateChatEncryptionProvider) != encryption) {
        return;
      }
      state = [
        for (final device in devices)
          if (device.status == EncryptionDeviceStatus.pending &&
              !device.current &&
              !_dismissed.contains(device.deviceId))
            device,
      ];
    } catch (error) {
      debugPrint('Failed to refresh encryption devices: $error');
    }
  }

  /// Hides a request on this device without deciding it; it stays pending for
  /// the account's other devices.
  void dismiss(String deviceId) {
    _dismissed.add(deviceId);
    state = [
      for (final device in state)
        if (device.deviceId != deviceId) device,
    ];
  }

  /// Removes a request this device approved or declined.
  void resolved(String deviceId) => dismiss(deviceId);
}
