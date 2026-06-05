import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/messaging/components/box/accord_message_content.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Channels the user has confirmed entry to this session, so the NSFW gate isn't
/// shown again until the app restarts. Keyed by channel id.
final _nsfwAcknowledged = <String>{};

/// Spaces whose rules the user has accepted this session.
final _rulesAccepted = <String>{};

/// Shows the age-restricted content gate for [channelName] if it hasn't already
/// been acknowledged this session for [channelId]. Returns true when the user
/// may proceed into the channel.
Future<bool> confirmNsfwGate(
  BuildContext context, {
  required String channelId,
  required String channelName,
}) async {
  if (_nsfwAcknowledged.contains(channelId)) return true;
  final colors = BonfireThemeExtension.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded, size: 44, color: colors.red),
                const SizedBox(height: 12),
                Text('Age-restricted channel',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  '#$channelName is marked for content that may not be suitable '
                  'for everyone. Are you over 18 and willing to view it?',
                  textAlign: TextAlign.center,
                  style:
                      theme.textTheme.bodyMedium!.copyWith(color: colors.gray),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Go back'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Continue'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  if (confirmed == true) {
    _nsfwAcknowledged.add(channelId);
    return true;
  }
  return false;
}

/// Shows the rules interstitial for [space] once per session if it has a rules
/// channel and the user hasn't accepted yet. Loads the rules channel's first
/// message as the rules text.
Future<void> maybeShowRulesInterstitial(
  BuildContext context,
  WidgetRef ref, {
  required AccordSpace space,
}) async {
  final rulesChannelId = space.rulesChannelId;
  if (rulesChannelId == null || _rulesAccepted.contains(space.id)) return;
  final client = ref.read(accordAuthProvider
      .select((s) => s is AccordAuthLoggedIn ? s.client : null));
  if (client == null) return;
  _rulesAccepted.add(space.id); // mark up-front to avoid repeated fetches
  final result = await client.messages.list(rulesChannelId, query: {'limit': 1});
  if (!context.mounted) return;
  final data = result.data;
  final messages = data is List ? data.whereType<AccordMessage>().toList() : null;
  final rulesText = (messages != null && messages.isNotEmpty)
      ? messages.first.content
      : 'Please follow this community\'s rules.';

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      final theme = Theme.of(context);
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Welcome to ${space.name}',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('Please review the rules before participating.',
                    style: theme.textTheme.bodySmall),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: AccordMessageContent(content: rulesText),
                  ),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('I agree'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
