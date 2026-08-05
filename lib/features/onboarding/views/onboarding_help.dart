import 'package:bonfire/shared/app_info.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Where "Help & support" points. Kept here rather than in `shared/app_info.dart`
/// so the onboarding module owns its own copy of the support surface; the repo
/// slug itself is still the single source of truth ([kGithubRepo]).
const String kDaccordHelpUrl = 'https://github.com/$kGithubRepo#readme';

/// The issue tracker — "found a bug / need help" lands here.
const String kDaccordIssuesUrl = 'https://github.com/$kGithubRepo/issues';

/// The wider project (server, protocol docs, the reference client).
const String kDaccordProjectUrl = 'https://github.com/DaccordProject';

/// One row of the help sheet.
@immutable
class OnboardingHelpLink {
  const OnboardingHelpLink({
    required this.label,
    required this.description,
    required this.url,
    required this.icon,
  });

  final String label;
  final String description;
  final String url;
  final IconData icon;
}

/// The support destinations offered from inside the walkthrough and from
/// Settings. Exposed (and pure) so a test can assert the set without launching
/// anything.
const List<OnboardingHelpLink> kOnboardingHelpLinks = <OnboardingHelpLink>[
  OnboardingHelpLink(
    label: 'Documentation',
    description: 'Setup, features and keyboard shortcuts.',
    url: kDaccordHelpUrl,
    icon: Icons.menu_book_outlined,
  ),
  OnboardingHelpLink(
    label: 'Report a problem',
    description: 'Search existing issues or open a new one.',
    url: kDaccordIssuesUrl,
    icon: Icons.bug_report_outlined,
  ),
  OnboardingHelpLink(
    label: 'The Daccord project',
    description: 'Servers, protocol docs and other clients.',
    url: kDaccordProjectUrl,
    icon: Icons.public,
  ),
];

/// Opens [url] in the platform browser, swallowing failures (a missing handler
/// on a headless/CI desktop must never take down the tour).
Future<void> openOnboardingHelpUrl(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('Failed to open help link $url: $e');
  }
}

/// The help/support sheet, reachable from every step of the walkthrough and from
/// the Settings row.
///
/// Deliberately a plain dialog rather than an in-app browser: the destinations
/// are external, and a first-launch user who is lost needs the real docs, not a
/// cut-down copy that will drift.
Future<void> showOnboardingHelpDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (dialogContext) {
    final colors = BonfireThemeExtension.of(dialogContext);
    return AlertDialog(
      icon: Icon(Icons.help_outline, color: colors.primary),
      title: const Text('Help & support'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final link in kOnboardingHelpLinks)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(link.icon, color: colors.primary),
                title: Text(link.label),
                subtitle: Text(link.description),
                trailing: const Icon(Icons.open_in_new, size: 16),
                onTap: () => openOnboardingHelpUrl(link.url),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).maybePop(),
          child: const Text('Close'),
        ),
      ],
    );
  },
);
