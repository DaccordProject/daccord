import 'dart:math';

import 'package:bonfire/features/authentication/utils/tos_gate.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// Generates a 16-character random password for the register flow's dice button.
String generateAuthPassword() {
  const chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%&*';
  final rng = Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i++) {
    buffer.write(chars[rng.nextInt(chars.length)]);
  }
  return buffer.toString();
}

/// Whether the credential form is capturing a sign-in or a new registration.
/// Shared by the primary login screen and the in-app Add-a-Server dialog so the
/// two surfaces present an identical sign-in / register experience.
enum AuthMode { signIn, register }

/// The shared credential-capture body: a Sign in / Register toggle, an optional
/// server-URL field, username, password (with an optional generator in register
/// mode), and — in register mode — a display name and Terms-of-Service gate.
///
/// This widget is purely presentational: it owns no provider calls and no submit
/// button. The host (login screen or Add-Server dialog) supplies the
/// controllers and renders its own error text, submit button, and any secondary
/// actions around it, so each can wire the appropriate auth method while sharing
/// one consistent form.
class AuthCredentialsFields extends StatelessWidget {
  const AuthCredentialsFields({
    super.key,
    required this.mode,
    required this.onModeChanged,
    this.serverController,
    required this.usernameController,
    required this.passwordController,
    required this.displayNameController,
    required this.tosAvailability,
    required this.tosAccepted,
    required this.onTosChanged,
    required this.onTosLinkTap,
    required this.onGeneratePassword,
    required this.onSubmit,
    this.enabled = true,
  });

  /// The active mode and a callback to switch it.
  final AuthMode mode;
  final ValueChanged<AuthMode> onModeChanged;

  /// When non-null, a Server-URL field is shown above the credentials (used by
  /// the login screen). The dialog omits it because the URL is entered first.
  final TextEditingController? serverController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final TextEditingController displayNameController;

  /// ToS gate, shown only in register mode: the checkbox when the server
  /// advertises terms, a note when the fetch failed and we can't tell.
  final TosAvailability tosAvailability;
  final bool tosAccepted;
  final ValueChanged<bool> onTosChanged;
  final VoidCallback onTosLinkTap;

  /// Fills the password field with a generated value (register mode only).
  final VoidCallback onGeneratePassword;

  /// Invoked when the user submits from the password (or last) field.
  final VoidCallback onSubmit;

  /// Disables all inputs while a request is in flight.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final isRegister = mode == AuthMode.register;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthModeToggle(
          mode: mode,
          onModeChanged: enabled ? onModeChanged : null,
        ),
        const SizedBox(height: 16),
        if (serverController != null) ...[
          AuthField(
            controller: serverController!,
            label: 'Server URL',
            hint: 'https://your.accord.server',
            enabled: enabled,
            keyboardType: TextInputType.url,
            autofillHints: const [AutofillHints.url],
          ),
          const SizedBox(height: 12),
        ],
        AuthField(
          controller: usernameController,
          // Registration creates a username (the public login id), so don't
          // imply an email is accepted; sign-in keeps the broader label.
          label: isRegister ? 'Username' : 'Username or email',
          enabled: enabled,
          autofillHints: const [AutofillHints.username],
        ),
        const SizedBox(height: 12),
        AuthPasswordField(
          controller: passwordController,
          enabled: enabled,
          autofillHints: const [AutofillHints.password],
          onGenerate: isRegister ? onGeneratePassword : null,
          onSubmitted: (_) => onSubmit(),
        ),
        if (isRegister) ...[
          const SizedBox(height: 12),
          AuthField(
            controller: displayNameController,
            label: 'Display name (optional)',
            enabled: enabled,
          ),
          if (tosAvailability == TosAvailability.advertised) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Checkbox(
                  value: tosAccepted,
                  onChanged:
                      enabled ? (v) => onTosChanged(v ?? false) : null,
                ),
                Text('I agree to the ', style: theme.textTheme.bodyMedium),
                GestureDetector(
                  onTap: onTosLinkTap,
                  child: Text(
                    'Terms of Service',
                    style: theme.textTheme.bodyMedium!.copyWith(
                      color: colors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ] else if (tosAvailability == TosAvailability.unknown) ...[
            // Not an error the user can act on, and never a blocker: the app's
            // own terms gate already ran. It exists so a server's terms can't
            // go missing silently (#289).
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: colors.dirtyWhite),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tosUnavailableNotice,
                    style: theme.textTheme.bodySmall!.copyWith(
                      color: colors.dirtyWhite,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}

/// The Sign in / Register pill toggle. A null [onModeChanged] disables it.
class AuthModeToggle extends StatelessWidget {
  const AuthModeToggle({
    super.key,
    required this.mode,
    required this.onModeChanged,
  });

  final AuthMode mode;
  final ValueChanged<AuthMode>? onModeChanged;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    Widget tab(String label, AuthMode value) {
      final selected = mode == value;
      return Expanded(
        child: GestureDetector(
          onTap: onModeChanged == null ? null : () => onModeChanged!(value),
          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? colors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleSmall!.copyWith(
                color: selected ? Colors.white : colors.dirtyWhite,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.darkGray,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          tab('Sign In', AuthMode.signIn),
          tab('Register', AuthMode.register),
        ],
      ),
    );
  }
}

/// A filled text field styled for the auth surfaces.
class AuthField extends StatelessWidget {
  const AuthField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.obscureText = false,
    this.enabled = true,
    this.keyboardType,
    this.autofillHints,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscureText;
  final bool enabled;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return TextField(
      controller: controller,
      obscureText: obscureText,
      enabled: enabled,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      onSubmitted: onSubmitted,
      style: Theme.of(context).textTheme.bodyLarge,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: colors.darkGray,
        labelStyle: Theme.of(context).textTheme.bodyMedium,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }
}

/// A password field with a show/hide toggle and an optional password generator.
class AuthPasswordField extends StatefulWidget {
  const AuthPasswordField({
    super.key,
    required this.controller,
    this.onGenerate,
    this.enabled = true,
    this.autofillHints,
    this.onSubmitted,
  });

  final TextEditingController controller;

  /// When non-null, a dice button is shown that fills a generated password and
  /// reveals it.
  final VoidCallback? onGenerate;
  final bool enabled;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AuthPasswordField> createState() => _AuthPasswordFieldState();
}

class _AuthPasswordFieldState extends State<AuthPasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return TextField(
      controller: widget.controller,
      obscureText: _obscure,
      enabled: widget.enabled,
      autofillHints: widget.autofillHints,
      onSubmitted: widget.onSubmitted,
      style: Theme.of(context).textTheme.bodyLarge,
      decoration: InputDecoration(
        labelText: 'Password',
        filled: true,
        fillColor: colors.darkGray,
        labelStyle: Theme.of(context).textTheme.bodyMedium,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onGenerate != null)
              IconButton(
                tooltip: 'Generate password',
                icon: Icon(Icons.casino, color: colors.dirtyWhite, size: 20),
                onPressed: () {
                  widget.onGenerate!();
                  setState(() => _obscure = false);
                },
              ),
            IconButton(
              tooltip: _obscure ? 'Show' : 'Hide',
              icon: Icon(
                _obscure ? Icons.visibility : Icons.visibility_off,
                color: colors.dirtyWhite,
                size: 20,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ],
        ),
      ),
    );
  }
}
