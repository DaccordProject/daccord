import 'package:bonfire/features/authentication/views/auth_form.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// Shared forced-password-reset form used by primary and add-server login.
class PasswordResetForm extends StatelessWidget {
  const PasswordResetForm({
    super.key,
    required this.oldController,
    required this.newController,
    required this.confirmController,
    required this.onSubmit,
    required this.onCancel,
    this.error,
    this.enabled = true,
  });

  final TextEditingController oldController;
  final TextEditingController newController;
  final TextEditingController confirmController;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;
  final String? error;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Change your password',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'The server requires a new password before you can continue',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFC8C8C8),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 32),
        AuthField(
          controller: oldController,
          label: 'Current password',
          obscureText: true,
          enabled: enabled,
        ),
        const SizedBox(height: 12),
        AuthField(
          controller: newController,
          label: 'New password',
          obscureText: true,
          enabled: enabled,
        ),
        const SizedBox(height: 12),
        AuthField(
          controller: confirmController,
          label: 'Confirm new password',
          obscureText: true,
          enabled: enabled,
          onSubmitted: (_) => enabled ? onSubmit() : null,
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(
            error!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium!.copyWith(
              color: BonfireThemeExtension.of(context).red,
            ),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: enabled ? onSubmit : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: BonfireThemeExtension.of(context).primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: enabled
                ? Text(
                    'Change Password',
                    style: theme.textTheme.titleSmall!.copyWith(
                      color: Colors.white,
                    ),
                  )
                : const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: enabled ? onCancel : null,
          child: Text('Cancel', style: theme.textTheme.bodyMedium),
        ),
      ],
    );
  }
}
