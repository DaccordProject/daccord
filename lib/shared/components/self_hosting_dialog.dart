import 'package:bonfire/features/onboarding/views/onboarding_help.dart'
    show openOnboardingHelpUrl;
import 'package:bonfire/shared/app_info.dart' show kGithubRepo;
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// The self-hosting guide (desktop tray app vs. a Docker/VPS deployment).
const String kDaccordSelfHostingUrl =
    'https://github.com/$kGithubRepo/blob/master/docs/self-hosting/overview.md';

/// Explains the two supported ways to host your own Accord server (the desktop
/// tray app, or an always-on Docker/VPS deployment) and how you get back into
/// the client afterwards. Mirrors `docs/self-hosting/overview.md`; the guide
/// itself is one tap away.
///
/// Self-hosting is a headline feature, so it has a presence on both signed-out
/// surfaces that would otherwise be mostly empty on a tablet — the welcome
/// screen and the server directory (#292).
///
/// [onConnect], when non-null, adds a "Connect by URL" action that closes the
/// dialog and hands back to the host's connect-by-URL flow.
Future<void> showSelfHostingDialog(
  BuildContext context, {
  VoidCallback? onConnect,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      final colors = BonfireThemeExtension.of(dialogContext);
      return AlertDialog(
        icon: Icon(Icons.home_work_outlined, color: colors.primary),
        title: const Text('Run your own server'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Daccord talks to Accord servers, and anyone can run one. '
                  'Your community keeps its own accounts, messages, uploads '
                  'and voice traffic — this app never proxies them.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.gray,
                  ),
                ),
                const SizedBox(height: 16),
                const _HostingOption(
                  icon: Icons.desktop_windows_outlined,
                  title: 'The Accord desktop app',
                  body:
                      'A tray app for Windows, macOS and Linux that bundles '
                      'the server and voice server and configures itself on '
                      'first launch. Best for friends and small communities.',
                ),
                const SizedBox(height: 12),
                const _HostingOption(
                  icon: Icons.dns_outlined,
                  title: 'A server deployment',
                  body:
                      'Run accordserver with Docker on a Linux machine or VPS '
                      'for an always-on community, with your own domain name '
                      'and HTTPS.',
                ),
                const SizedBox(height: 16),
                Text(
                  'Once it is running, come back here and connect with its URL.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.gray,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          if (onConnect != null)
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                onConnect();
              },
              child: const Text('Connect by URL'),
            ),
          FilledButton(
            onPressed: () => openOnboardingHelpUrl(kDaccordSelfHostingUrl),
            child: const Text('Read the guide'),
          ),
        ],
      );
    },
  );
}

class _HostingOption extends StatelessWidget {
  const _HostingOption({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: colors.dirtyWhite),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                body,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.gray),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
