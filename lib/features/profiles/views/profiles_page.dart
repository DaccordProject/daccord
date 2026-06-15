import 'package:bonfire/features/profiles/controllers/profiles_controller.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:bonfire/shared/components/settings_scaffold.dart';
import 'package:bonfire/features/profiles/models/device_profile.dart';
import 'package:bonfire/features/profiles/views/app_restart.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the device-profiles management page (create / switch / rename / delete
/// / PIN-lock local profiles). Ports the reference's
/// `user_settings_profiles_page.gd`.
Future<void> showProfilesSettings(BuildContext context) {
  return Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const ProfilesScreen()));
}

class ProfilesScreen extends ConsumerWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final profiles = ref.watch(profilesControllerProvider);
    final notifier = ref.read(profilesControllerProvider.notifier);
    final activeId = notifier.activeId;

    return SettingsScaffold(
      title: 'Device Profiles',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createProfile(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New profile'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 88),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Profiles are isolated local spaces, each with its own accounts '
              'and settings. Switching restarts the app.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall!.copyWith(color: colors.gray),
            ),
          ),
          for (final p in profiles)
            _ProfileTile(
              profile: p,
              isActive: p.id == activeId,
              onSwitch: () => _switch(context, ref, p.id),
              onRename: () => _rename(context, ref, p),
              onDelete: p.isDefault ? null : () => _delete(context, ref, p),
              onTogglePin: () => _togglePin(context, ref, p),
            ),
        ],
      ),
    );
  }

  Future<void> _switch(BuildContext context, WidgetRef ref, String id) async {
    final notifier = ref.read(profilesControllerProvider.notifier);
    if (id == notifier.activeId) return;
    await notifier.switchProfile(id);
    if (context.mounted) AppRestart.restart(context);
  }

  Future<void> _createProfile(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<({String name, String pin})>(
      context: context,
      builder: (_) => const _CreateProfileDialog(),
    );
    if (result == null || result.name.trim().isEmpty) return;
    ref
        .read(profilesControllerProvider.notifier)
        .create(result.name, pin: result.pin.isEmpty ? null : result.pin);
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    DeviceProfile p,
  ) async {
    final name = await _promptText(context, 'Rename profile', p.name);
    if (name == null) return;
    ref.read(profilesControllerProvider.notifier).rename(p.id, name);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    DeviceProfile p,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete profile',
      message:
          "Delete '${p.name}' and all its accounts and settings? This cannot "
          'be undone.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (confirmed != true) return;
    await ref.read(profilesControllerProvider.notifier).delete(p.id);
  }

  Future<void> _togglePin(
    BuildContext context,
    WidgetRef ref,
    DeviceProfile p,
  ) async {
    final notifier = ref.read(profilesControllerProvider.notifier);
    if (p.hasPin) {
      // Require the current PIN before clearing it.
      final pin = await _promptText(
        context,
        'Enter current PIN to remove',
        '',
        obscure: true,
        number: true,
      );
      if (pin == null) return;
      if (!notifier.verifyPin(p.id, pin)) {
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(
            context,
          )?.showSnackBar(const SnackBar(content: Text('Incorrect PIN')));
        }
        return;
      }
      notifier.setPin(p.id, null);
      return;
    }
    final pin = await _promptText(
      context,
      'Set a PIN',
      '',
      obscure: true,
      number: true,
    );
    if (pin == null || pin.isEmpty) return;
    notifier.setPin(p.id, pin);
  }

  Future<String?> _promptText(
    BuildContext context,
    String title,
    String initial, {
    bool obscure = false,
    bool number = false,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: obscure,
          keyboardType: number ? TextInputType.number : null,
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.profile,
    required this.isActive,
    required this.onSwitch,
    required this.onRename,
    required this.onDelete,
    required this.onTogglePin,
  });

  final DeviceProfile profile;
  final bool isActive;
  final VoidCallback onSwitch;
  final VoidCallback onRename;
  final VoidCallback? onDelete;
  final VoidCallback onTogglePin;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isActive ? colors.primary : colors.darkGray,
        child: Icon(
          profile.hasPin ? Icons.lock : Icons.person,
          color: Colors.white,
          size: 20,
        ),
      ),
      title: Row(
        children: [
          Flexible(child: Text(profile.name, overflow: TextOverflow.ellipsis)),
          if (isActive) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Active',
                style: TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        profile.hasPin ? 'PIN protected' : 'No PIN',
        style: Theme.of(
          context,
        ).textTheme.bodySmall!.copyWith(color: colors.gray),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          switch (v) {
            case 'switch':
              onSwitch();
            case 'rename':
              onRename();
            case 'pin':
              onTogglePin();
            case 'delete':
              onDelete?.call();
          }
        },
        itemBuilder: (_) => [
          if (!isActive)
            const PopupMenuItem(value: 'switch', child: Text('Switch to')),
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(
            value: 'pin',
            child: Text(profile.hasPin ? 'Remove PIN' : 'Set PIN'),
          ),
          if (onDelete != null)
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}

/// Dialog collecting a new profile's name and optional PIN.
class _CreateProfileDialog extends StatefulWidget {
  const _CreateProfileDialog();

  @override
  State<_CreateProfileDialog> createState() => _CreateProfileDialogState();
}

class _CreateProfileDialogState extends State<_CreateProfileDialog> {
  final _name = TextEditingController();
  final _pin = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New profile'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Profile name'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'PIN (optional)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop((name: _name.text, pin: _pin.text)),
          child: const Text('Create'),
        ),
      ],
    );
  }
}
