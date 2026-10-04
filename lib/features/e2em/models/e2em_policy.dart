import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:bonfire/features/e2em/models/e2em_preferences.dart';

/// Additive composition for the future versioned space policy API. Space rules
/// cannot shadow personal rules, and personal opt-out never disables space rules.
/// Platform policies must be validated by the provider before they can be used.
Map<String, dynamic> composeE2emPolicy({
  required E2emPreferences personal,
  E2emPreferences? requiredSpace,
}) {
  personal.validate();
  requiredSpace?.validate();
  final rules = <Map<String, dynamic>>[];
  void add(E2emPreferences preferences, String source) {
    for (final category in preferences.categories) {
      final detected = category == 'pii.email';
      rules.add({
        'id': '$source-${rules.length}',
        'category': category,
        'directions': ['outgoing'],
        'match': detected ? 'detected' : 'score',
        'action': preferences.response.name,
        'context_requirement': 'target_only',
        if (!detected) ...{
          'review_threshold': preferences.threshold * 0.5,
          'action_threshold': preferences.threshold,
          'model_thresholds': false,
        },
      });
    }
    for (final text in preferences.customRules) {
      rules.add({
        'id': '$source-custom-${rules.length}',
        'policy_text': text,
        'directions': ['outgoing'],
        'match': 'policy_text',
        'action': preferences.response.name,
        'context_requirement': 'target_only',
      });
    }
  }

  if (personal.enabled) add(personal, 'personal');
  if (requiredSpace != null) add(requiredSpace, 'space');
  if (rules.length > 64) {
    throw const FormatException('The combined E2EM policy exceeds 64 rules.');
  }
  final policy = <String, dynamic>{
    'schema_version': '0.1',
    'id': 'daccord-outgoing',
    'profile': requiredSpace == null ? 'personal' : 'platform',
    'rules': rules,
    'default_action': 'allow',
    'on_error': 'review',
    'on_indeterminate': 'review',
    'override':
        requiredSpace != null || personal.response == E2emResponse.review
        ? 'forbidden'
        : 'user_confirm',
  };
  policy['version'] = sha256
      .convert(utf8.encode(jsonEncode(policy)))
      .toString();
  return policy;
}
