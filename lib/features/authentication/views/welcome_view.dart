import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// First-run / signed-out landing screen: daccord branding, a short pitch, and
/// the primary path into the public server browser. The Flutter port of the
/// reference client's `welcome_screen` — clean and static (no shader/particles),
/// with a single fade-in entrance.
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

  static const _features = [
    (
      icon: Icons.dns_outlined,
      title: 'Multi-Server',
      subtitle: 'Connect to multiple servers at once',
    ),
    (
      icon: Icons.chat_bubble_outline,
      title: 'Real-Time Chat',
      subtitle: 'Instant messaging with rich formatting',
    ),
    (
      icon: Icons.videocam_outlined,
      title: 'Voice & Video',
      subtitle: 'Crystal-clear voice and video calls',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 16), child: child),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Image.asset('assets/images/icon.png', width: 84, height: 84),
          ),
          const SizedBox(height: 16),
          Text(
            'Daccord',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Connect. Communicate. Collaborate.',
            textAlign: TextAlign.center,
            style: GoogleFonts.publicSans(
              color: const Color(0xFFC8C8C8),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 28),
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = [
                for (final f in _features)
                  _FeatureCard(
                    icon: f.icon,
                    title: f.title,
                    subtitle: f.subtitle,
                    colors: colors,
                    theme: theme,
                  ),
              ];
              if (constraints.maxWidth < 420) {
                return Column(
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      cards[i],
                    ],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: cards[i]),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 28),
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
              'Connect to a server',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (onSwitchAccount != null)
            TextButton(
              onPressed: onSwitchAccount,
              child: Text(
                'Switch account',
                style: theme.textTheme.bodyMedium,
              ),
            ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.theme,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final BonfireThemeExtension colors;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: colors.foreground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 26, color: colors.primary),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: colors.gray),
          ),
        ],
      ),
    );
  }
}
