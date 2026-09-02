import 'package:flutter_test/flutter_test.dart';

import '../../tool/store_capture/seeded_space.dart';

/// App Store guideline 2.3.10 (#291, #304).
///
/// iOS 0.2.16 was rejected for a third-party platform name in the screenshots.
/// The tablet captures now render the app against the fixture in
/// `tool/store_capture/seeded_space.dart`, so whatever that file says is what a
/// reviewer reads. This is the one part of the capture harness worth running on
/// every commit: it is a string scan, and the failure it prevents costs a
/// review cycle.
///
/// The harness itself is not a test — see `docs/app-store-deploy.md`.
const _bannedFragments = <String>[
  // Other platforms and products.
  'discord', 'slack', 'telegram', 'whatsapp', 'signal ', 'element',
  'teams', 'zoom', 'skype', 'irc', 'android', 'windows', 'linux', 'ios',
  'macos', 'iphone', 'ipad', 'google', 'apple', 'meta', 'facebook',
  // The app's own distribution, which screenshots must not narrate.
  'app store', 'play store', 'testflight', 'review',
];

void main() {
  test('no seeded string names another platform or the store', () {
    final strings = <String>[
      for (final space in seedSpaces) space['name'] as String,
      for (final channel in [...seedValeChannels, ...seedTideChannels])
        channel['name'] as String,
      for (final channel in [...seedValeChannels, ...seedTideChannels])
        if (channel['topic'] != null) channel['topic'] as String,
      for (final member in [...seedValeMembers, ...seedTideMembers]) ...[
        member.displayName,
        member.username,
      ],
      for (final message in [
        ...seedGeneralMessages,
        ...seedTideMessages,
        ...seedVoiceChatMessages,
      ])
        message['content'] as String,
    ];

    for (final value in strings) {
      final lower = value.toLowerCase();
      for (final banned in _bannedFragments) {
        expect(
          lower.contains(banned),
          isFalse,
          reason: 'seeded string "$value" contains "$banned"',
        );
      }
    }
  });

  test('the fixture still covers what the scenes need', () {
    // A capture is only worth taking if the message pane has something to
    // prove: a reply, a mention and reactions all have to be on screen.
    expect(
      seedGeneralMessages.any((m) => m['reply_to'] != null),
      isTrue,
      reason: 'no reply to render',
    );
    expect(
      seedGeneralMessages.any((m) => m['mentions'] != null),
      isTrue,
      reason: 'no mention to render',
    );
    expect(
      seedGeneralMessages.where((m) => m['reactions'] != null).length,
      greaterThanOrEqualTo(2),
      reason: 'too few reacted messages',
    );
    // The rail only reads as multi-server with several spaces in it.
    expect(seedSpaces.length, greaterThanOrEqualTo(5));
    // Grouped roster sections need hoisted roles and mostly-online members.
    expect(
      seedValeMembers.where((m) => m.status == 'offline').length,
      lessThan(seedValeMembers.length ~/ 2),
    );
  });
}
