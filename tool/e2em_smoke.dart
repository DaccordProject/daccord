import 'dart:io';

// Read-only local integration check. No chat message is sent to a server.
// Run: dart run tool/e2em_smoke.dart [enrolled-app-name]
import 'package:bonfire/features/e2em/models/e2em_policy.dart';
import 'package:bonfire/features/e2em/models/e2em_preferences.dart';
import 'package:e2em_local/e2em.dart';

Future<void> main(List<String> args) async {
  final client = await Client.connect(
    app: args.isEmpty ? 'daccord' : args.single,
  );
  try {
    final policy = composeE2emPolicy(
      personal: const E2emPreferences(enabled: true, categories: ['pii.email']),
    );
    await client.validatePolicy(policy);
    final plain = messageRequest('Hello there', policies: ['pii.email'])
      ..['policy'] = policy;
    final ordinary = await client.assess(plain);
    if (ordinary.status != 'assessed' ||
        ordinary.action != 'allow' ||
        !ordinary.appliesTo(plain)) {
      throw StateError('Ordinary text failed its local check.');
    }
    final sensitive = messageRequest(
      'Contact me at test@example.com',
      policies: ['pii.email'],
    )..['policy'] = policy;
    final warning = await client.assess(sensitive);
    if (warning.status != 'assessed' ||
        warning.action != 'warn' ||
        !warning.appliesTo(sensitive)) {
      throw StateError('Email warning failed its local check.');
    }
    await client.validatePolicy(
      composeE2emPolicy(personal: const E2emPreferences(enabled: true)),
    );
    await client.validatePolicy(
      composeE2emPolicy(
        personal: const E2emPreferences(
          enabled: true,
          categories: ['pii.email'],
          customRules: ['Keep launch dates private.'],
          response: E2emResponse.review,
        ),
      ),
    );
    stdout.writeln(
      'Local E2EM: ordinary text allowed; email warned; standard and custom policies validated.',
    );
  } finally {
    client.close();
  }
}
