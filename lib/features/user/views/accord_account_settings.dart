import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the account settings dialog: change password and manage two-factor
/// authentication. The Accord analogue of Discord's "My Account" panel.
Future<void> showAccordAccountSettings(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _AccountSettingsDialog(),
  );
}

class _AccountSettingsDialog extends ConsumerStatefulWidget {
  const _AccountSettingsDialog();

  @override
  ConsumerState<_AccountSettingsDialog> createState() =>
      _AccountSettingsDialogState();
}

class _AccountSettingsDialogState
    extends ConsumerState<_AccountSettingsDialog> {
  bool? _mfaEnabled;

  @override
  void initState() {
    super.initState();
    _loadMfaState();
  }

  AccordClient? get _client => ref.read(
    accordAuthProvider.select((s) => s is AccordAuthLoggedIn ? s.client : null),
  );

  Future<void> _loadMfaState() async {
    final client = _client;
    if (client == null) return;
    final result = await client.users.getMe();
    if (!mounted) return;
    final user = result.data;
    setState(() {
      _mfaEnabled = user is AccordUser ? user.mfaEnabled : false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Dialog(
      backgroundColor: colors.foreground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 600),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Account settings',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, size: 20, color: colors.gray),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'PASSWORD',
                style: theme.textTheme.labelSmall!.copyWith(
                  color: colors.gray,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const _PasswordSection(),
              const SizedBox(height: 20),
              Divider(height: 1, color: colors.background),
              const SizedBox(height: 16),
              Text(
                'TWO-FACTOR AUTHENTICATION',
                style: theme.textTheme.labelSmall!.copyWith(
                  color: colors.gray,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (_mfaEnabled == null)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                _TwoFactorSection(
                  enabled: _mfaEnabled!,
                  onChanged: (v) => setState(() => _mfaEnabled = v),
                ),
              const SizedBox(height: 20),
              Divider(height: 1, color: colors.background),
              const SizedBox(height: 16),
              Text(
                'DANGER ZONE',
                style: theme.textTheme.labelSmall!.copyWith(
                  color: colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const _DangerZoneSection(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Account-deletion section: password + type-to-confirm "DELETE", calling
/// `users.deleteMe` then removing the account locally. Ports the reference's
/// `user_settings_danger.gd`.
class _DangerZoneSection extends ConsumerStatefulWidget {
  const _DangerZoneSection();

  @override
  ConsumerState<_DangerZoneSection> createState() => _DangerZoneSectionState();
}

class _DangerZoneSectionState extends ConsumerState<_DangerZoneSection> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  AccordClient? get _client => ref.read(
    accordAuthProvider.select((s) => s is AccordAuthLoggedIn ? s.client : null),
  );

  Future<void> _delete() async {
    final client = _client;
    if (client == null || _busy) return;
    if (_password.text.isEmpty) {
      setState(() => _error = 'Password is required');
      return;
    }
    if (_confirm.text.trim() != 'DELETE') {
      setState(() => _error = "Type DELETE to confirm");
      return;
    }
    final session = ref.read(accordAuthProvider);
    if (session is! AccordAuthLoggedIn) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await client.users.deleteMe({'password': _password.text});
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _busy = false;
        _error = result.error?.toString() ?? 'Failed to delete account';
      });
      return;
    }
    // Account gone server-side — drop it locally (switches to another server
    // or signs out when none remain).
    await ref.read(accordAuthProvider.notifier).removeAccount(session.session);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Permanently deletes your account on this server, including your '
          'profile, messages, and memberships. This cannot be undone.',
          style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _password,
          enabled: !_busy,
          obscureText: true,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'Password',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _confirm,
          enabled: !_busy,
          decoration: const InputDecoration(
            isDense: true,
            labelText: "Type DELETE to confirm",
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: theme.textTheme.bodySmall!.copyWith(color: colors.red),
          ),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: _busy ? null : _delete,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_forever, size: 18),
            label: const Text('Delete my account'),
          ),
        ),
      ],
    );
  }
}

class _PasswordSection extends ConsumerStatefulWidget {
  const _PasswordSection();

  @override
  ConsumerState<_PasswordSection> createState() => _PasswordSectionState();
}

class _PasswordSectionState extends ConsumerState<_PasswordSection> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _success = false;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final client = ref.read(
      accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.client : null,
      ),
    );
    if (client == null) return;
    final oldPw = _old.text;
    final newPw = _new.text;
    if (oldPw.isEmpty || newPw.length < 6) {
      setState(() {
        _success = false;
        _message = 'Enter your current password and a new one (6+ chars)';
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final result = await client.auth.changePassword({
      'old_password': oldPw,
      'new_password': newPw,
    });
    if (!mounted) return;
    setState(() {
      _busy = false;
      _success = result.ok;
      _message = result.ok
          ? 'Password updated'
          : result.error?.toString() ?? 'Failed to change password';
      if (result.ok) {
        _old.clear();
        _new.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _old,
          enabled: !_busy,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Current password',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _new,
          enabled: !_busy,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'New password',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        if (_message != null) ...[
          const SizedBox(height: 8),
          Text(
            _message!,
            style: theme.textTheme.bodySmall!.copyWith(
              color: _success ? colors.green : colors.red,
            ),
          ),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _busy ? null : _submit,
            child: const Text('Change password'),
          ),
        ),
      ],
    );
  }
}

class _TwoFactorSection extends ConsumerStatefulWidget {
  const _TwoFactorSection({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  ConsumerState<_TwoFactorSection> createState() => _TwoFactorSectionState();
}

class _TwoFactorSectionState extends ConsumerState<_TwoFactorSection> {
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  // Set after a successful enable() call: the secret/otpauth the user must add
  // to their authenticator before verifying.
  String? _secret;
  String? _otpauth;
  List<String>? _backupCodes;

  @override
  void dispose() {
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  AccordClient? get _client => ref.read(
    accordAuthProvider.select((s) => s is AccordAuthLoggedIn ? s.client : null),
  );

  Future<void> _enable() async {
    final client = _client;
    if (client == null) return;
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await client.auth.enable2fa({'password': _password.text});
    if (!mounted) return;
    final data = result.data;
    setState(() {
      _busy = false;
      if (result.ok && data is Map) {
        _secret = data['secret']?.toString();
        _otpauth = data['otpauth_uri']?.toString() ?? data['uri']?.toString();
      } else {
        _error = result.error?.toString() ?? 'Failed to start 2FA setup';
      }
    });
  }

  Future<void> _verify() async {
    final client = _client;
    if (client == null) return;
    if (_code.text.trim().isEmpty) {
      setState(() => _error = 'Enter the 6-digit code');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await client.auth.verify2fa({'code': _code.text.trim()});
    if (!mounted) return;
    final data = result.data;
    setState(() {
      _busy = false;
      if (result.ok) {
        _backupCodes = data is Map && data['backup_codes'] is List
            ? (data['backup_codes'] as List).map((e) => e.toString()).toList()
            : null;
        _secret = null;
        _otpauth = null;
        _password.clear();
        _code.clear();
        widget.onChanged(true);
      } else {
        _error = result.error?.toString() ?? 'Invalid code';
      }
    });
  }

  Future<void> _disable() async {
    final client = _client;
    if (client == null) return;
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your password to disable 2FA');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await client.auth.disable2fa({'password': _password.text});
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.ok) {
        _password.clear();
        _backupCodes = null;
        widget.onChanged(false);
      } else {
        _error = result.error?.toString() ?? 'Failed to disable 2FA';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);

    if (_backupCodes != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '2FA is now enabled. Save these backup codes:',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.darkGray,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              _backupCodes!.join('\n'),
              style: theme.textTheme.bodyMedium!.copyWith(
                fontFeatures: const [],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => Clipboard.setData(
                ClipboardData(text: _backupCodes!.join('\n')),
              ),
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy codes'),
            ),
          ),
        ],
      );
    }

    if (widget.enabled) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user, size: 18, color: colors.green),
              const SizedBox(width: 8),
              Text('2FA is enabled', style: theme.textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _password,
            enabled: !_busy,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: theme.textTheme.bodySmall!.copyWith(color: colors.red),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _busy ? null : _disable,
              style: TextButton.styleFrom(foregroundColor: colors.red),
              child: const Text('Disable 2FA'),
            ),
          ),
        ],
      );
    }

    // Not yet enabled: either prompt for password (start), or show the secret +
    // verification field after enable() succeeded.
    final setupStarted = _secret != null || _otpauth != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!setupStarted) ...[
          Text(
            'Protect your account with an authenticator app.',
            style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _password,
            enabled: !_busy,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: theme.textTheme.bodySmall!.copyWith(color: colors.red),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _busy ? null : _enable,
              child: const Text('Enable 2FA'),
            ),
          ),
        ] else ...[
          Text(
            'Add this secret to your authenticator app, then enter the code:',
            style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.darkGray,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              _secret ?? _otpauth ?? '',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _code,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '6-digit code',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: theme.textTheme.bodySmall!.copyWith(color: colors.red),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _busy ? null : _verify,
              child: const Text('Verify & activate'),
            ),
          ),
        ],
      ],
    );
  }
}
