import 'dart:convert';

enum E2emResponse { warn, review }

/// Daccord's selectable outgoing categories, rather than every runtime preset.
const e2emCategories = <String, ({String label, String group})>{
  'pii.email': (label: 'Email addresses', group: 'Privacy and secrets'),
  'pii.phone': (label: 'Phone numbers', group: 'Privacy and secrets'),
  'cred.secret_token': (
    label: 'Passwords and API keys',
    group: 'Privacy and secrets',
  ),
  'fin.card_number': (
    label: 'Payment card numbers',
    group: 'Privacy and secrets',
  ),
  'privacy.doxxing': (
    label: 'Sharing someone’s private details',
    group: 'Privacy and secrets',
  ),
  'abuse.harassment': (label: 'Bullying and harassment', group: 'Abuse'),
  'abuse.threat': (label: 'Threats', group: 'Abuse'),
  'identity.hate': (label: 'Hate speech', group: 'Abuse'),
  'sexual.harassment': (label: 'Sexual harassment', group: 'Abuse'),
  'sexual.explicit': (
    label: 'Explicit sexual text',
    group: 'Sensitive content',
  ),
  'sexual.minors': (
    label: 'Sexual content involving children',
    group: 'Sensitive content',
  ),
  'violence.instruction': (
    label: 'Violent threats and instructions',
    group: 'Sensitive content',
  ),
  'self_harm.encouragement': (
    label: 'Self-harm encouragement',
    group: 'Sensitive content',
  ),
  'profanity.strong': (label: 'Strong profanity', group: 'Sensitive content'),
  'spam.mass_mention': (label: 'Mass mentions', group: 'Spam and scams'),
  'spam.promotion': (label: 'Unsolicited promotion', group: 'Spam and scams'),
  'fraud.financial_solicitation': (
    label: 'Financial solicitation',
    group: 'Spam and scams',
  ),
};

const e2emStandardCategories = [
  'pii.email',
  'cred.secret_token',
  'abuse.threat',
  'identity.hate',
];

/// Personal settings contain no runtime credentials and travel with the profile.
class E2emPreferences {
  const E2emPreferences({
    this.enabled = false,
    this.categories = e2emStandardCategories,
    this.customRules = const [],
    this.response = E2emResponse.warn,
    this.threshold = 0.7,
  });

  final bool enabled;
  final List<String> categories;
  final List<String> customRules;
  final E2emResponse response;
  final double threshold;

  bool get hasRules => categories.isNotEmpty || customRules.isNotEmpty;

  E2emPreferences copyWith({
    bool? enabled,
    List<String>? categories,
    List<String>? customRules,
    E2emResponse? response,
    double? threshold,
  }) => E2emPreferences(
    enabled: enabled ?? this.enabled,
    categories: List.unmodifiable(categories ?? this.categories),
    customRules: List.unmodifiable(customRules ?? this.customRules),
    response: response ?? this.response,
    threshold: threshold ?? this.threshold,
  );

  void validate() {
    if (!threshold.isFinite ||
        threshold < 0.1 ||
        threshold > 1 ||
        categories.length + customRules.length > 64 ||
        categories.toSet().length != categories.length ||
        categories.any((id) => !e2emCategories.containsKey(id)) ||
        customRules.any(
          (text) => text.trim().isEmpty || utf8.encode(text).length > 512,
        )) {
      throw const FormatException('Invalid E2EM rules.');
    }
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'categories': categories,
    'customRules': customRules,
    'response': response.name,
    'threshold': threshold,
  };

  factory E2emPreferences.fromJson(Object? raw) {
    if (raw == null) return const E2emPreferences();
    if (raw is! Map) throw const FormatException('Invalid E2EM settings.');
    final response = raw['response'] as String? ?? 'warn';
    if (!E2emResponse.values.asNameMap().containsKey(response)) {
      throw const FormatException('Invalid E2EM response.');
    }
    final result = E2emPreferences(
      enabled: raw['enabled'] as bool? ?? false,
      categories: List<String>.unmodifiable(
        raw['categories'] as List? ?? e2emStandardCategories,
      ),
      customRules: List<String>.unmodifiable(
        raw['customRules'] as List? ?? const [],
      ),
      response: E2emResponse.values.byName(response),
      threshold: (raw['threshold'] as num?)?.toDouble() ?? 0.7,
    );
    result.validate();
    return result;
  }
}
