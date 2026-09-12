import 'dart:convert';

Map<String, dynamic> copyAutomodJson(Map<String, dynamic> value) =>
    (jsonDecode(jsonEncode(value)) as Map).cast<String, dynamic>();

const automodTriggers = {
  'media': 'Image/video content',
  'hash_denylist': 'Blocked file',
  'low_trust': 'New or untrusted member',
  'non_nsfw_attachment': 'Attachment outside an NSFW channel',
};
const automodActions = {
  'quarantine': 'Hold for review',
  'reject': 'Reject',
  'flag': 'Publish and report',
  'timeout': 'Hold and time out member',
};
bool automodAllowsTimeout(String trigger) =>
    trigger == 'hash_denylist' || trigger == 'low_trust';

/// Validate the editable policy before sending its complete replacement.
String? validateAutomodPolicy(Map<String, dynamic> policy) {
  final retention = policy['retention_days'];
  if (retention is! int || retention < 1 || retention > 90) {
    return 'Keep evidence for between 1 and 90 days.';
  }
  final rules = policy['rules'];
  if (rules is! List || rules.length > 32) return 'Use at most 32 rules.';
  final ids = <String>{};
  for (final rule in rules) {
    if (rule is! Map) return 'Invalid rule. Update the client before editing.';
    final id = rule['id'];
    if (id is! String ||
        id.isEmpty ||
        utf8.encode(id).length > 64 ||
        !ids.add(id)) {
      return 'Each rule needs a unique name of at most 64 bytes.';
    }
    final trigger = automodMap(rule['trigger']);
    final action = automodMap(rule['action']);
    final scope = automodMap(rule['scope']);
    if (!['all', 'non_nsfw', 'channels'].contains(scope['type'])) {
      return 'Unsupported channel scope.';
    }
    if (!automodTriggers.containsKey(trigger['type']) ||
        !automodActions.containsKey(action['type'])) {
      return 'This policy uses a rule type this client cannot edit. Update the client first.';
    }
    if (trigger['type'] == 'media') {
      final threshold = trigger['threshold'];
      final categories = trigger['categories'];
      if (threshold is! num ||
          !threshold.isFinite ||
          threshold < 0 ||
          threshold > 1 ||
          categories is! List ||
          categories.isEmpty ||
          categories.length > 64 ||
          categories.any(
            (c) => c is! String || c.isEmpty || utf8.encode(c).length > 64,
          )) {
        return 'Content rules need detector categories and a threshold between 0 and 1.';
      }
    }
    if (scope['type'] == 'channels' &&
        (automodList(scope['ids']).isEmpty ||
            automodList(scope['ids']).length > 100)) {
      return 'Choose between 1 and 100 channels for a channel-specific rule.';
    }
    if (action['type'] == 'timeout') {
      final seconds = action['seconds'];
      if (!automodAllowsTimeout(trigger['type'] as String) ||
          seconds is! int ||
          seconds < 1 ||
          seconds > 86400) {
        return 'Timeouts require a blocked-file or trust rule and a duration of 1–86400 seconds.';
      }
    }
  }
  return null;
}

Map<String, dynamic> automodMap(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};
List<dynamic> automodList(Object? value) =>
    value is List ? List<dynamic>.of(value) : <dynamic>[];
