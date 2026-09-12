import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/utils/send_cooldown.dart';
import 'package:flutter_test/flutter_test.dart';

/// The composer's slowmode / rate-limit cooldown logic (#330), tested as pure
/// functions: exemption, the local timer after a send, the server's 429
/// overriding it, what Send is blocked by, and the countdown wording.

final _t0 = DateTime.utc(2026, 1, 1, 12);

AccordChannel _channel(Object? rateLimit) =>
    AccordChannel.fromJson({'id': 'c1', 'rate_limit': rateLimit});

RestResult _rateLimited(int seconds) => RestResult.failure(
  429,
  AccordError(
    code: 'rate_limited',
    message: 'rate limited, retry after ${seconds}s',
    retryAfter: Duration(seconds: seconds),
  ),
);

void main() {
  group('isSlowmodeExempt', () {
    test('a plain member is not exempt', () {
      expect(
        isSlowmodeExempt(
          channelPermissions: {AccordPermission.sendMessages},
          isSpaceOwner: false,
          isInstanceAdmin: false,
        ),
        isFalse,
      );
      expect(
        isSlowmodeExempt(
          channelPermissions: const {},
          isSpaceOwner: false,
          isInstanceAdmin: false,
        ),
        isFalse,
      );
    });

    test('effective manage_messages or manage_channels exempts', () {
      expect(
        isSlowmodeExempt(
          channelPermissions: {AccordPermission.manageMessages},
          isSpaceOwner: false,
          isInstanceAdmin: false,
        ),
        isTrue,
      );
      expect(
        isSlowmodeExempt(
          channelPermissions: {AccordPermission.manageChannels},
          isSpaceOwner: false,
          isInstanceAdmin: false,
        ),
        isTrue,
      );
      // `administrator` implies every permission.
      expect(
        isSlowmodeExempt(
          channelPermissions: {AccordPermission.administrator},
          isSpaceOwner: false,
          isInstanceAdmin: false,
        ),
        isTrue,
      );
    });

    test('space owners and instance admins are exempt regardless', () {
      expect(
        isSlowmodeExempt(
          channelPermissions: const {},
          isSpaceOwner: true,
          isInstanceAdmin: false,
        ),
        isTrue,
      );
      expect(
        isSlowmodeExempt(
          channelPermissions: const {},
          isSpaceOwner: false,
          isInstanceAdmin: true,
        ),
        isTrue,
      );
    });
  });

  group('effectiveSlowmodeSeconds', () {
    test('reads the channel rate_limit tolerantly', () {
      expect(
        effectiveSlowmodeSeconds(channel: _channel(30), exempt: false),
        30,
      );
      expect(
        effectiveSlowmodeSeconds(channel: _channel('30'), exempt: false),
        30,
      );
      expect(effectiveSlowmodeSeconds(channel: _channel(0), exempt: false), 0);
      expect(
        effectiveSlowmodeSeconds(channel: _channel(null), exempt: false),
        0,
      );
      expect(effectiveSlowmodeSeconds(channel: null, exempt: false), 0);
    });

    test('is 0 for an exempt user', () {
      expect(effectiveSlowmodeSeconds(channel: _channel(30), exempt: true), 0);
    });
  });

  group('cooldownAfterSend', () {
    test('starts a slowmode cooldown for the channel interval', () {
      final cooldown = cooldownAfterSend(slowmodeSeconds: 30, now: _t0);
      expect(cooldown, isNotNull);
      expect(cooldown!.kind, SendCooldownKind.slowmode);
      expect(cooldown.until, _t0.add(const Duration(seconds: 30)));
      expect(cooldown.isActive(_t0), isTrue);
      expect(cooldown.remaining(_t0), const Duration(seconds: 30));
      final later = _t0.add(const Duration(seconds: 30));
      expect(cooldown.isActive(later), isFalse);
      expect(cooldown.remaining(later), Duration.zero);
      expect(
        cooldown.remaining(later.add(const Duration(seconds: 5))),
        Duration.zero,
      );
    });

    test('is nothing without slowmode', () {
      expect(cooldownAfterSend(slowmodeSeconds: 0, now: _t0), isNull);
      expect(cooldownAfterSend(slowmodeSeconds: -1, now: _t0), isNull);
    });
  });

  group('SendFailure.fromResult', () {
    test('carries the server message and retry_after for a 429', () {
      final failure = SendFailure.fromResult(_rateLimited(12), 'fallback');
      expect(failure.rateLimited, isTrue);
      expect(failure.retryAfter, const Duration(seconds: 12));
      expect(failure.message, 'rate limited, retry after 12s');
    });

    test('treats a 429 without a parsed code as a rate limit too', () {
      final failure = SendFailure.fromResult(
        RestResult.failure(429, AccordError(code: 'INTERNAL', message: '')),
        'fallback',
      );
      expect(failure.rateLimited, isTrue);
      expect(failure.retryAfter, isNull);
      expect(failure.message, 'fallback');
    });

    test('is a plain failure for anything else', () {
      final failure = SendFailure.fromResult(
        RestResult.failure(403, AccordError(code: 'FORBIDDEN', message: 'no')),
        'fallback',
      );
      expect(failure.rateLimited, isFalse);
      expect(failure.retryAfter, isNull);
      expect(failure.message, 'no');
    });
  });

  group('cooldownFromFailure', () {
    test('a 429 in a slowmode channel corrects the local timer', () {
      final failure = SendFailure.fromResult(_rateLimited(12), '');
      final cooldown = cooldownFromFailure(
        failure: failure,
        slowmodeSeconds: 30,
        now: _t0,
      );
      expect(cooldown!.kind, SendCooldownKind.rateLimited);
      // The server's 12s wins over the channel's 30s.
      expect(cooldown.until, _t0.add(const Duration(seconds: 12)));
    });

    test('a 429 without slowmode is a generic rate limit', () {
      final failure = SendFailure.fromResult(_rateLimited(45), '');
      final cooldown = cooldownFromFailure(
        failure: failure,
        slowmodeSeconds: 0,
        now: _t0,
      );
      expect(cooldown!.kind, SendCooldownKind.rateLimited);
      expect(cooldown.until, _t0.add(const Duration(seconds: 45)));
    });

    test('a 429 without a usable retry_after waits the SDK default', () {
      const failure = SendFailure('rate limited', rateLimited: true);
      final cooldown = cooldownFromFailure(
        failure: failure,
        slowmodeSeconds: 0,
        now: _t0,
      );
      expect(cooldown!.until, _t0.add(AccordRest.defaultRetryAfter));
    });

    test('a zero retry_after and a non-rate-limit failure start nothing', () {
      expect(
        cooldownFromFailure(
          failure: const SendFailure(
            'now',
            rateLimited: true,
            retryAfter: Duration.zero,
          ),
          slowmodeSeconds: 30,
          now: _t0,
        ),
        isNull,
      );
      expect(
        cooldownFromFailure(
          failure: const SendFailure('File too large'),
          slowmodeSeconds: 30,
          now: _t0,
        ),
        isNull,
      );
    });
  });

  test('a generic text 429 blocks another text send until its deadline', () {
    final cooldown = cooldownFromFailure(
      failure: SendFailure.fromResult(_rateLimited(12), ''),
      slowmodeSeconds: 0, now: _t0,
    );
    expect(sendBlockedByCooldown(cooldown: cooldown, now: _t0, hasAttachments: false), isTrue);
    expect(sendBlockedByCooldown(cooldown: cooldown, now: _t0.add(const Duration(seconds: 12)), hasAttachments: false), isFalse);
  });
  group('sendBlockedByCooldown', () {
    final slowmode = SendCooldown(
      until: _t0.add(const Duration(seconds: 30)),
      kind: SendCooldownKind.slowmode,
    );
    final rateLimited = SendCooldown(
      uploadsOnly: true,
      until: _t0.add(const Duration(seconds: 30)),
      kind: SendCooldownKind.rateLimited,
    );

    test('slowmode blocks text and uploads alike', () {
      expect(
        sendBlockedByCooldown(
          cooldown: slowmode,
          now: _t0,
          hasAttachments: false,
        ),
        isTrue,
      );
      expect(
        sendBlockedByCooldown(
          cooldown: slowmode,
          now: _t0,
          hasAttachments: true,
        ),
        isTrue,
      );
    });

    test('an upload-budget limit only blocks a send carrying files', () {
      expect(
        sendBlockedByCooldown(
          cooldown: rateLimited,
          now: _t0,
          hasAttachments: true,
        ),
        isTrue,
      );
      // Drop the files and text goes through in a channel without slowmode.
      expect(
        sendBlockedByCooldown(
          cooldown: rateLimited,
          now: _t0,
          hasAttachments: false,
        ),
        isFalse,
      );
    });

    test('nothing blocks once the deadline passes, or with no cooldown', () {
      final after = _t0.add(const Duration(seconds: 30));
      expect(
        sendBlockedByCooldown(
          cooldown: slowmode,
          now: after,
          hasAttachments: true,
        ),
        isFalse,
      );
      expect(
        sendBlockedByCooldown(cooldown: null, now: _t0, hasAttachments: true),
        isFalse,
      );
    });
  });

  group('wording', () {
    test('formatCooldown rounds up and scales to minutes and hours', () {
      expect(formatCooldown(const Duration(seconds: 12)), '12s');
      expect(formatCooldown(const Duration(milliseconds: 11400)), '12s');
      expect(formatCooldown(const Duration(milliseconds: 200)), '1s');
      expect(formatCooldown(Duration.zero), '0s');
      expect(formatCooldown(const Duration(seconds: 65)), '1m 5s');
      expect(formatCooldown(const Duration(seconds: 600)), '10m 0s');
      expect(formatCooldown(const Duration(seconds: 21600)), '6h 0m');
      expect(formatCooldown(const Duration(seconds: 3661)), '1h 1m');
    });

    test('sendCooldownLabel names slowmode vs a plain rate limit', () {
      final slowmode = SendCooldown(
        until: _t0.add(const Duration(seconds: 12)),
        kind: SendCooldownKind.slowmode,
      );
      expect(
        sendCooldownLabel(slowmode, _t0),
        'Slow mode: you can send again in 12s',
      );
      final limited = SendCooldown(
        until: _t0.add(const Duration(seconds: 45)),
        kind: SendCooldownKind.rateLimited,
      );
      expect(
        sendCooldownLabel(limited, _t0),
        'Rate limited — try again in 45s',
      );
    });

    test('slowmodeHint describes the interval', () {
      expect(slowmodeHint(30), 'Slow mode is on: one message every 30s');
      expect(slowmodeHint(300), 'Slow mode is on: one message every 5m 0s');
    });
  });
}
