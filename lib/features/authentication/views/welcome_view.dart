import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// First-run / signed-out landing screen: daccord branding, a short pitch, and
/// the primary path into the public server browser. The Flutter port of the
/// reference client's `welcome_screen`, kept deliberately compact so choosing
/// a server remains visible on narrow devices.
///
/// [onBrowse] opens the server browser (the default next step); [onManualConnect]
/// jumps straight to the connect-by-URL credentials form; [onSwitchAccount], when
/// non-null, surfaces a link back to saved accounts.
class WelcomeView extends StatelessWidget {
  const WelcomeView({
    super.key,
    required this.onBrowse,
    required this.onManualConnect,
    this.onSwitchAccount,
  });

  final VoidCallback onBrowse;
  final VoidCallback onManualConnect;
  final VoidCallback? onSwitchAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Image.asset('assets/images/icon.png', width: 76, height: 76),
        ),
        const SizedBox(height: 14),
        Text(
          'Daccord',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose an Accord community to start messaging, voice, and video on '
          'infrastructure you control or trust.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(color: colors.gray),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 50,
          child: ElevatedButton.icon(
            onPressed: onBrowse,
            icon: const Icon(Icons.explore_outlined, size: 20),
            label: const Text('Browse Servers'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: Colors.white,
              textStyle: theme.textTheme.titleSmall,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onManualConnect,
          child: Text(
            'Connect directly to a server',
            style: theme.textTheme.bodyMedium,
          ),
        ),
        if (onSwitchAccount != null)
          TextButton(
            onPressed: onSwitchAccount,
            child: Text('Switch account', style: theme.textTheme.bodyMedium),
          ),
      ],
    );
  }
}
