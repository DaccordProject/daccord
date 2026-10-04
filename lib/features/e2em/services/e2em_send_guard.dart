import 'dart:convert';
import 'dart:math';

import 'package:accordkit/accordkit.dart';

import 'package:bonfire/features/e2em/models/e2em_policy.dart';
import 'package:bonfire/features/e2em/models/e2em_preferences.dart';
import 'package:bonfire/features/e2em/services/e2em_runtime.dart';

/// Guard the handed-off send snapshot. Subsequent composer input is a new draft.
/// No warning confirmation or error ever retries the network operation.
class E2emSendGuard {
  E2emSendGuard({
    required this.runtime,
    required this.preferences,
    required this.confirmWarning,
    required this.isSessionCurrent,
  });

  final E2emRuntime runtime;
  final E2emPreferences Function() preferences;
  final Future<bool> Function(String text, List<String> categories)
  confirmWarning;
  final bool Function() isSessionCurrent;

  Future<MessageSendCheck> call(
    String channelId,
    Map<String, dynamic> data,
  ) async {
    if (!isSessionCurrent()) {
      return _hold('The account changed. Please try again.');
    }
    final selected = preferences();
    final settingsSnapshot = jsonEncode(selected.toJson());
    bool current() =>
        isSessionCurrent() &&
        jsonEncode(preferences().toJson()) == settingsSnapshot;
    if (!selected.enabled || !selected.hasRules) {
      return MessageSendCheck.allow(isCurrent: current);
    }
    if (!runtime.supported) {
      return _hold(
        'E2EM checks are enabled, but this device is not supported yet.',
      );
    }
    // Embeds contain additional text and legacy API callers can supply them.
    // Hold rather than imply that checking just `content` covers that payload.
    if (data['embeds'] != null &&
        (data['embeds'] is! List || (data['embeds'] as List).isNotEmpty)) {
      return _hold(
        'E2EM cannot assess outgoing embeds yet. Remove the embed before sending.',
      );
    }
    final content = data['content'];
    if (content != null && content is! String) {
      return _hold('Invalid message text.');
    }
    final text = content as String? ?? '';
    // File contents are outside this text-only preview. Captions are assessed.
    if (text.isEmpty) return MessageSendCheck.allow(isCurrent: current);
    try {
      final policy = composeE2emPolicy(personal: selected);
      final requestId = List.generate(
        16,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final request = <String, dynamic>{
        'api_version': '0.1',
        'request_id': requestId,
        'direction': 'outgoing',
        'message': {
          'id': requestId,
          'revision': '1',
          'speaker': 'self',
          'text': text,
        },
        'context': <Map<String, dynamic>>[],
        'policy': policy,
        'options': {'deadline_ms': 15000},
      };
      final report = await runtime.assess(request);
      if (!current() || !report.appliesTo(request)) {
        return _hold('E2EM settings changed while checking. Please try again.');
      }
      if (report.status != 'assessed' || !report.complete) {
        return _hold(
          'E2EM could not complete every required check. Your message was held; try again.',
        );
      }
      if (report.action == 'warn') {
        if (policy['override'] != 'user_confirm' ||
            !await confirmWarning(text, report.categories)) {
          return _hold('Message held. Edit your draft before sending again.');
        }
      } else if (report.action != 'allow') {
        return _hold(
          'Your E2EM rules held this message for review. Edit your draft before sending again.',
        );
      }
      return MessageSendCheck.allow(isCurrent: current);
    } on E2emUnavailable {
      return _hold(
        'E2EM is unavailable. Your message was held. Check E2EM in Settings and try again.',
      );
    } on FormatException {
      return _hold(
        'Your E2EM rules are invalid. Review them in Settings before sending.',
      );
    } catch (_) {
      return _hold(
        'E2EM could not check this message. Your draft was held; try again.',
      );
    }
  }

  MessageSendCheck _hold(String message) =>
      MessageSendCheck.hold(AccordError(code: 'e2em_held', message: message));
}
