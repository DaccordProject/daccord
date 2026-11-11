import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/messaging/controllers/private_chat_devices.dart';
import 'package:bonfire/features/messaging/views/private_chat_security.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String _errorText(Object error) =>
    error is EncryptionException ? error.message : 'Something went wrong.';

/// Hosts the "approve new device" prompt above every route, beside the
/// incoming-call and turn banners, so a request made from a new phone reaches
/// whichever already-approved device the user is looking at.
Widget withDeviceApprovalPrompts(Widget? child) => Stack(
  children: [
    if (child != null) Positioned.fill(child: child),
    const Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(child: _DeviceApprovalBanner()),
    ),
    // Positioned, like everything here: a non-positioned child would size the
    // Stack to itself under loose constraints, collapsing the app to 0×0.
    const Positioned(left: 0, top: 0, child: _SetupReloader()),
  ],
);

/// Reloads private history once this device is approved: everything fetched
/// while pending was cached as "not approved yet" placeholders.
class _SetupReloader extends ConsumerWidget {
  const _SetupReloader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(privateChatSetupProvider, (previous, next) {
      if (previous?.value != null &&
          previous?.value != PrivateChatSetup.active &&
          next.value == PrivateChatSetup.active) {
        ref.invalidate(accordMessagesControllerProvider);
      }
    });
    return const SizedBox.shrink();
  }
}

class _DeviceApprovalBanner extends ConsumerStatefulWidget {
  const _DeviceApprovalBanner();

  @override
  ConsumerState<_DeviceApprovalBanner> createState() =>
      _DeviceApprovalBannerState();
}

class _DeviceApprovalBannerState extends ConsumerState<_DeviceApprovalBanner> {
  bool _busy = false;
  String? _error;
  String? _codeFor;
  Future<String>? _code;

  Future<void> _decide(
    PrivateChatEncryption encryption,
    EncryptionDevice device, {
    required bool approve,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (approve) {
        await encryption.approveDevice(device.deviceId);
      } else {
        await encryption.declineDevice(device.deviceId);
      }
      ref
          .read(pendingDeviceRequestsProvider.notifier)
          .resolved(device.deviceId);
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(pendingDeviceRequestsProvider);
    final encryption = ref.watch(privateChatEncryptionProvider);
    if (requests.isEmpty || encryption == null) return const SizedBox.shrink();
    final device = requests.first;
    if (_codeFor != device.deviceId) {
      _codeFor = device.deviceId;
      _code = encryption.linkCodeFor(device);
      _error = null;
    }
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Material(
          elevation: 4,
          color: theme.colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.devices_other_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Let “${device.name}” read your encrypted chats?',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Approve only if you are signing in on that device and it '
                  'shows this code:',
                ),
                const SizedBox(height: 4),
                FutureBuilder<String>(
                  future: _code,
                  builder: (context, snapshot) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _LinkCode(
                        code: snapshot.data,
                        error: snapshot.hasError
                            ? _errorText(snapshot.error!)
                            : null,
                      ),
                      if (_error != null)
                        Text(
                          _error!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      _actions(
                        encryption,
                        device,
                        // Approval is only meaningful once the user has a
                        // code to compare; the SDK refuses it before then.
                        codeShown: snapshot.hasData,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actions(
    PrivateChatEncryption encryption,
    EncryptionDevice device, {
    required bool codeShown,
  }) => Align(
    alignment: Alignment.centerRight,
    child: Wrap(
      spacing: 8,
      children: [
        TextButton(
          onPressed: _busy
              ? null
              : () => ref
                    .read(pendingDeviceRequestsProvider.notifier)
                    .dismiss(device.deviceId),
          child: const Text('Not now'),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => _decide(encryption, device, approve: false),
          child: const Text('Decline'),
        ),
        FilledButton(
          onPressed: _busy || !codeShown
              ? null
              : () => _decide(encryption, device, approve: true),
          child: const Text('Approve'),
        ),
      ],
    ),
  );
}

/// A 16-digit comparison code in large, selectable, spaced digits.
class _LinkCode extends StatelessWidget {
  const _LinkCode({this.code, this.error});

  final String? code;
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Text(
        error!,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }
    if (code == null) return const LinearProgressIndicator();
    return SelectableText(
      code!,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
        letterSpacing: 2,
      ),
    );
  }
}

/// Shown above a private conversation (and the DM list) while this device has
/// not been approved: its messages can't be decrypted until it is.
class PrivateChatSetupBanner extends ConsumerWidget {
  const PrivateChatSetupBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setup = ref.watch(privateChatSetupProvider).value;
    final encryption = ref.watch(privateChatEncryptionProvider);
    if (encryption == null) return const SizedBox.shrink();
    final (icon, message, action) = switch (setup) {
      PrivateChatSetup.pending => (
        Icons.lock_clock_outlined,
        'Encrypted messages can’t be read on this device until you approve '
            'it from a device you already use.',
        'Set up',
      ),
      PrivateChatSetup.approved => (
        Icons.lock_clock_outlined,
        'Another device approved this one. Confirm the code to finish '
            'setting up encrypted chats.',
        'Confirm',
      ),
      // The SDK says why: a key mismatch, or (on servers without device
      // approval) another device holding the account's identity.
      PrivateChatSetup.blocked => (
        Icons.gpp_bad_outlined,
        encryption.blockedReason,
        'Details',
      ),
      _ => (null, null, null),
    };
    if (icon == null || message == null || action == null) {
      return const SizedBox.shrink();
    }
    final colors = BonfireThemeExtension.of(context);
    return Material(
      color: colors.foreground,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: colors.dirtyWhite),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
            TextButton(
              onPressed: () => setup == PrivateChatSetup.blocked
                  ? showPrivateChatSecurity(context, encryption, null)
                  : showDeviceLinkDialog(context, encryption),
              child: Text(action),
            ),
          ],
        ),
      ),
    );
  }
}

/// Walks a pending device through approval: shows its comparison code, waits
/// for another device to approve it, and offers a backup import instead.
Future<void> showDeviceLinkDialog(
  BuildContext context,
  PrivateChatEncryption encryption,
) => showDialog<void>(
  context: context,
  builder: (_) => _DeviceLinkDialog(encryption: encryption),
);

class _DeviceLinkDialog extends StatefulWidget {
  const _DeviceLinkDialog({required this.encryption});

  final PrivateChatEncryption encryption;

  @override
  State<_DeviceLinkDialog> createState() => _DeviceLinkDialogState();
}

class _DeviceLinkDialogState extends State<_DeviceLinkDialog> {
  late Future<String> _code = widget.encryption.linkCode();
  late PrivateChatSetup _setupState = widget.encryption.setup;
  StreamSubscription<PrivateChatSetup>? _setup;
  Timer? _poll;
  bool _checking = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _setup = widget.encryption.setupChanges.listen(_onSetup);
    // The gateway usually announces the approval; polling covers a dropped
    // connection while the dialog is open.
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _check());
  }

  void _onSetup(PrivateChatSetup setup) {
    if (!mounted) return;
    if (setup == PrivateChatSetup.active) return _done();
    setState(() {
      // Re-registering (declined, expired, or the account key moved) gives
      // this device a new code: never keep showing a stale one.
      if (setup == PrivateChatSetup.pending) {
        _code = widget.encryption.linkCode();
      }
      _setupState = setup;
    });
  }

  Future<void> _check() async {
    if (_checking || _setupState != PrivateChatSetup.pending) return;
    _checking = true;
    try {
      await widget.encryption.checkApproval();
    } catch (_) {
      // Approval not available yet; the next tick or gateway event retries.
    } finally {
      _checking = false;
    }
  }

  /// The second half of the comparison: the other device approved, and only
  /// the user can say it showed this device's code. Until then the received
  /// keys stay staged and unused.
  Future<void> _confirm({required bool matched}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (matched) {
        await widget.encryption.confirmApproval();
      } else {
        await widget.encryption.rejectApproval();
      }
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _done() {
    if (!mounted) return;
    _poll?.cancel();
    final navigator = Navigator.of(context);
    showInfoSnack(context, 'This device can now read your encrypted chats.');
    navigator.pop();
  }

  @override
  void dispose() {
    _setup?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final approved = _setupState == PrivateChatSetup.approved;
    return AlertDialog(
      title: const Text('Set up encrypted chats'),
      content: SizedBox(
        width: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              approved
                  ? 'Your other device approved this one. Did it show this '
                        'same code?'
                  : 'Open Daccord on a device that already shows your '
                        'encrypted chats. It will ask to approve this device — '
                        'check that it shows the same code, then approve.',
            ),
            const SizedBox(height: 16),
            FutureBuilder<String>(
              future: _code,
              builder: (context, snapshot) => _LinkCode(
                code: snapshot.data,
                error: snapshot.hasError ? _errorText(snapshot.error!) : null,
              ),
            ),
            const SizedBox(height: 16),
            if (approved)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : () => _confirm(matched: false),
                    child: const Text('It showed a different code'),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : () => _confirm(matched: true),
                    child: const Text('Codes match'),
                  ),
                ],
              )
            else
              const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Expanded(child: Text('Waiting for approval…')),
                ],
              ),
            if (_busy) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 16),
            Text(
              'No other device? Import an encrypted backup instead.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              showPrivateChatSecurity(context, widget.encryption, null),
          child: const Text('Import backup'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// This account's devices: approve or decline new ones, and remove lost ones.
/// Removing rotates the account key so the removed device can't read anything
/// sent afterwards; the remaining devices pick up the new key automatically.
Future<void> showEncryptionDevices(
  BuildContext context,
  PrivateChatEncryption encryption,
) => showDialog<void>(
  context: context,
  builder: (_) => _DevicesDialog(encryption: encryption),
);

class _DevicesDialog extends StatefulWidget {
  const _DevicesDialog({required this.encryption});

  final PrivateChatEncryption encryption;

  @override
  State<_DevicesDialog> createState() => _DevicesDialogState();
}

class _DevicesDialogState extends State<_DevicesDialog> {
  late Future<List<EncryptionDevice>> _devices = widget.encryption
      .listDevices();
  StreamSubscription<void>? _updates;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _updates = widget.encryption.onDevicesUpdate.listen((_) => _reload());
  }

  @override
  void dispose() {
    _updates?.cancel();
    super.dispose();
  }

  void _reload() {
    if (mounted) {
      setState(() => _devices = widget.encryption.listDevices());
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      _reload();
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(EncryptionDevice device) async {
    final code = await widget.encryption.linkCodeFor(device);
    if (!mounted) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Approve “${device.name}”?',
      message:
          'Approve only if that device shows this code:\n\n$code\n\n'
          'It will be able to read all of your encrypted chats.',
      confirmLabel: 'Approve',
    );
    if (confirmed == true) {
      await _run(() => widget.encryption.approveDevice(device.deviceId));
    }
  }

  Future<void> _remove(EncryptionDevice device) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove “${device.name}”?',
      message:
          'It will be signed out and can’t read encrypted messages sent '
          'from now on. Messages it already has stay on it. Your other '
          'devices switch to a new encryption key automatically.',
      confirmLabel: 'Remove',
      danger: true,
    );
    if (confirmed == true) {
      await _run(() => widget.encryption.removeDevices([device.deviceId]));
    }
  }

  String _subtitle(BuildContext context, EncryptionDevice device) {
    if (device.current) return 'This device';
    if (device.status == EncryptionDeviceStatus.pending) {
      return 'Waiting for approval';
    }
    final seen = device.lastSeenAt;
    if (seen == null) return 'Approved';
    return 'Last active '
        '${MaterialLocalizations.of(context).formatMediumDate(seen.toLocal())}';
  }

  @override
  Widget build(BuildContext context) {
    final canManage = widget.encryption.setup == PrivateChatSetup.active;
    return AlertDialog(
      title: const Text('Devices'),
      content: SizedBox(
        width: 460,
        child: FutureBuilder<List<EncryptionDevice>>(
          future: _devices,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text(_errorText(snapshot.error!));
            final devices = snapshot.data;
            if (devices == null) return const LinearProgressIndicator();
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'These devices can read your encrypted chats. Remove any '
                  'you no longer use or don’t recognise.',
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final device in devices)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            device.status == EncryptionDeviceStatus.pending
                                ? Icons.hourglass_top
                                : Icons.devices_outlined,
                          ),
                          title: Text(device.name),
                          subtitle: Text(_subtitle(context, device)),
                          trailing: !canManage || device.current || _busy
                              ? null
                              : device.status == EncryptionDeviceStatus.pending
                              ? Wrap(
                                  children: [
                                    TextButton(
                                      onPressed: () => _run(
                                        () => widget.encryption.declineDevice(
                                          device.deviceId,
                                        ),
                                      ),
                                      child: const Text('Decline'),
                                    ),
                                    TextButton(
                                      onPressed: () => _approve(device),
                                      child: const Text('Approve'),
                                    ),
                                  ],
                                )
                              : TextButton(
                                  onPressed: () => _remove(device),
                                  child: Text(
                                    'Remove',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                ),
                        ),
                    ],
                  ),
                ),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
