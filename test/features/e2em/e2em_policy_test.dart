import 'package:bonfire/features/e2em/models/e2em_policy.dart';
import 'package:bonfire/features/e2em/models/e2em_preferences.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:flutter_test/flutter_test.dart';

List<Map<String, dynamic>> rules(Map<String, dynamic> policy) =>
    (policy['rules'] as List).cast<Map<String, dynamic>>();

void main() {
  test(
    'old settings leave E2EM off; configured rules survive a backup round trip',
    () {
      expect(AccordSettings.fromJson({}).e2em.enabled, isFalse);
      final configured = const AccordSettings().copyWith(
        e2em: const E2emPreferences(
          enabled: true,
          categories: ['abuse.threat'],
          customRules: ['Keep launch dates private.'],
          response: E2emResponse.review,
          threshold: 0.5,
        ),
      );
      expect(
        AccordSettings.fromJson(configured.toJson()).e2em.toJson(),
        configured.e2em.toJson(),
      );
      expect(
        configured.copyWith(soundsEnabled: false).e2em,
        same(configured.e2em),
      );
    },
  );

  test(
    'strict personal rules survive a permissive space with overlapping categories',
    () {
      const personal = E2emPreferences(
        enabled: true,
        categories: ['abuse.threat'],
        customRules: ['Do not share meeting locations.'],
        response: E2emResponse.review,
        threshold: 0.3,
      );
      const space = E2emPreferences(
        categories: ['abuse.threat'],
        threshold: 0.9,
      );
      final baseline = rules(composeE2emPolicy(personal: personal));
      final combined = composeE2emPolicy(
        personal: personal,
        requiredSpace: space,
      );
      // The space adds a separate requirement; it never replaces personal action,
      // threshold, or custom text merely because a category/name overlaps.
      expect(rules(combined).take(baseline.length), baseline);
      expect(rules(combined).last['action_threshold'], 0.9);
      expect(
        rules(combined).map((r) => r['id']).toSet().length,
        rules(combined).length,
      );
      expect(combined['override'], 'forbidden');
      expect(combined['profile'], 'platform');
    },
  );

  test('personal opt-out does not disable a mandatory space requirement', () {
    final policy = composeE2emPolicy(
      personal: const E2emPreferences(),
      requiredSpace: const E2emPreferences(
        categories: ['sexual.explicit'],
        response: E2emResponse.review,
        threshold: 0.4,
      ),
    );
    expect(rules(policy).single['category'], 'sexual.explicit');
    expect(rules(policy).single['action'], 'review');
    expect(policy['override'], 'forbidden');
  });

  test('identical custom wording remains independently owned', () {
    const selected = E2emPreferences(
      enabled: true,
      categories: [],
      customRules: ['No launch dates.'],
    );
    final combined = rules(
      composeE2emPolicy(personal: selected, requiredSpace: selected),
    );
    expect(combined.length, 2);
    expect(combined.first['id'], startsWith('personal-'));
    expect(combined.last['id'], startsWith('space-'));
  });

  test(
    'a combined policy over the provider limit fails rather than dropping protections',
    () {
      final many = E2emPreferences(
        enabled: true,
        categories: [],
        customRules: List.generate(64, (i) => 'Keep secret $i private.'),
      );
      expect(
        () => composeE2emPolicy(
          personal: many,
          requiredSpace: const E2emPreferences(categories: ['pii.email']),
        ),
        throwsFormatException,
      );
    },
  );

  test('invalid imported rules are rejected rather than silently weakened', () {
    for (final bad in [
      {
        'enabled': true,
        'categories': ['unknown-rule'],
      },
      {'enabled': true, 'response': 'allow'},
      {'enabled': true, 'threshold': 0},
      {
        'enabled': true,
        'customRules': ['🙂' * 129],
      },
    ]) {
      expect(() => E2emPreferences.fromJson(bad), throwsA(isA<Exception>()));
    }
  });

  test('policy versions change with action, sensitivity, and custom text', () {
    const selected = E2emPreferences(enabled: true);
    final original = composeE2emPolicy(personal: selected)['version'];
    for (final changed in [
      selected.copyWith(response: E2emResponse.review),
      selected.copyWith(threshold: 0.5),
      selected.copyWith(customRules: ['No launch dates.']),
    ]) {
      expect(composeE2emPolicy(personal: changed)['version'], isNot(original));
    }
  });
}
