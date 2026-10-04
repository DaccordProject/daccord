import 'dart:convert';

import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/shared/components/section_header.dart';
import 'package:bonfire/shared/components/settings_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bonfire/features/e2em/models/e2em_policy.dart';
import 'package:bonfire/features/e2em/models/e2em_preferences.dart';
import 'package:bonfire/features/e2em/services/e2em_runtime.dart';

class E2emSettingsSection extends ConsumerWidget {
  const E2emSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionHeader('E2EM'),
      ListTile(
        leading: const Icon(Icons.shield_outlined),
        title: const Text('Personal content rules'),
        subtitle: Text(
          ref.watch(settingsControllerProvider).e2em.enabled
              ? 'Check outgoing text before sending'
              : 'Local message checks are off',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const E2emSettingsPage()),
        ),
      ),
    ],
  );
}

class E2emSettingsPage extends ConsumerStatefulWidget {
  const E2emSettingsPage({super.key});

  @override
  ConsumerState<E2emSettingsPage> createState() => _E2emSettingsPageState();
}

class _E2emSettingsPageState extends ConsumerState<E2emSettingsPage> {
  E2emRuntimeStatus? _status;
  String? _checkedPolicy;
  bool _busy = false;

  void _save(E2emPreferences value) {
    ref.read(settingsControllerProvider.notifier).setE2em(value);
    setState(() {
      _status = null;
      _checkedPolicy = null;
    });
  }

  Future<void> _check() async {
    final selected = ref.read(settingsControllerProvider).e2em;
    // Validate the configured rules even while the personal switch is off.
    final policy = composeE2emPolicy(
      personal: selected.copyWith(enabled: true),
    );
    final version = jsonEncode(policy);
    setState(() => _busy = true);
    E2emRuntimeStatus status;
    try {
      status = await ref.read(e2emRuntimeProvider).check(policy);
    } catch (_) {
      status = const E2emRuntimeStatus(
        false,
        'Unable to check E2EM. Try again.',
      );
    }
    if (!mounted) return;
    final now = composeE2emPolicy(
      personal: ref
          .read(settingsControllerProvider)
          .e2em
          .copyWith(enabled: true),
    );
    setState(() {
      _busy = false;
      if (jsonEncode(now) == version) {
        _status = status;
        _checkedPolicy = version;
      }
    });
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      await ref.read(e2emRuntimeProvider).connectApp();
      if (!mounted) return;
      setState(
        () => _status = const E2emRuntimeStatus(
          false,
          'Approve “Connect app” in E2EM setup, then check the connection here.',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _status = const E2emRuntimeStatus(
          false,
          'Unable to open E2EM setup. Open it manually and connect the app “daccord”.',
        ),
      );
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _addCustomRule() async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => const _CustomRuleDialog(),
    );
    if (value == null || !mounted) return;
    final current = ref.read(settingsControllerProvider).e2em;
    if (current.categories.length + current.customRules.length >= 64) return;
    _save(current.copyWith(customRules: [...current.customRules, value]));
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(settingsControllerProvider).e2em;
    final supported = ref.watch(e2emRuntimeProvider).supported;
    final currentPolicy = jsonEncode(
      composeE2emPolicy(personal: preferences.copyWith(enabled: true)),
    );
    final status = _checkedPolicy == null || _checkedPolicy == currentPolicy
        ? _status
        : null;
    return SettingsScaffold(
      title: 'E2EM',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'E2EM checks outgoing message text locally before sending. '
            'Your personal rules stay on this profile and are not shared with space owners.',
          ),
          const SizedBox(height: 12),
          const Text(
            'This preview covers outgoing text on desktop. Incoming messages, '
            'files, images, voice, and video are not checked. Space requirements will '
            'be added when the server and runtime support mandatory policies.',
          ),
          if (!supported) ...[
            const SizedBox(height: 12),
            const Text(
              'The current E2EM SDK does not support this device. '
              'You can edit your saved rules here. Enabled checks hold text sends until support is available.',
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Check outgoing text'),
            subtitle: const Text(
              'Unavailable or incomplete checks hold the draft.',
            ),
            value: preferences.enabled,
            onChanged: !supported && !preferences.enabled
                ? null
                : (enabled) => _save(preferences.copyWith(enabled: enabled)),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: supported && !_busy ? _connect : null,
                child: const Text('Connect Daccord to E2EM'),
              ),
              OutlinedButton(
                onPressed: supported && !_busy ? _check : null,
                child: Text(_busy ? 'Checking…' : 'Check connection and rules'),
              ),
            ],
          ),
          if (status != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(status.message, key: const ValueKey('e2em-status')),
            ),
          const Divider(height: 32),
          SectionHeader('Starting rules'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => _save(
                  preferences.copyWith(categories: e2emStandardCategories),
                ),
                child: const Text('Standard'),
              ),
              OutlinedButton(
                onPressed: () => _save(
                  preferences.copyWith(
                    categories: e2emCategories.keys.toList(),
                    response: E2emResponse.review,
                    threshold: 0.5,
                  ),
                ),
                child: const Text('Strict'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          RadioGroup<E2emResponse>(
            groupValue: preferences.response,
            onChanged: (value) {
              if (value != null) _save(preferences.copyWith(response: value));
            },
            child: const Column(
              children: [
                RadioListTile<E2emResponse>(
                  contentPadding: EdgeInsets.zero,
                  value: E2emResponse.warn,
                  title: Text('Warn before sending'),
                  subtitle: Text(
                    'Ask for confirmation when a rule flags the draft.',
                  ),
                ),
                RadioListTile<E2emResponse>(
                  contentPadding: EdgeInsets.zero,
                  value: E2emResponse.review,
                  title: Text('Hold for editing'),
                  subtitle: Text(
                    'Keep flagged drafts without a send-anyway option.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Detection sensitivity: ${((1 - preferences.threshold) * 100).round()}%',
          ),
          Slider(
            value: 1 - preferences.threshold,
            min: 0,
            max: 0.9,
            divisions: 9,
            onChanged: (value) => _save(
              preferences.copyWith(threshold: (1 - value).clamp(0.1, 1.0)),
            ),
          ),
          const Text(
            'Higher sensitivity flags more text and may flag harmless messages. '
            'Uncertain assessments are held for review. Email patterns do not use this slider. '
            'Custom rules use the model’s own threshold.',
          ),
          if (!preferences.hasRules)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No rules selected. Outgoing text will not be checked.',
              ),
            ),
          for (final group
              in e2emCategories.values.map((v) => v.group).toSet()) ...[
            const SizedBox(height: 16),
            SectionHeader(group),
            for (final entry in e2emCategories.entries.where(
              (e) => e.value.group == group,
            ))
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.value.label),
                value: preferences.categories.contains(entry.key),
                onChanged: (selected) {
                  final next = [...preferences.categories];
                  if (selected == true) {
                    if (next.length + preferences.customRules.length >= 64) {
                      return;
                    }
                    next.add(entry.key);
                  } else {
                    next.remove(entry.key);
                  }
                  _save(preferences.copyWith(categories: next));
                },
              ),
          ],
          const SizedBox(height: 16),
          SectionHeader('Custom rules'),
          for (var i = 0; i < preferences.customRules.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(preferences.customRules[i]),
              trailing: IconButton(
                tooltip: 'Remove custom rule',
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  final next = [...preferences.customRules]..removeAt(i);
                  _save(preferences.copyWith(customRules: next));
                },
              ),
            ),
          OutlinedButton.icon(
            onPressed:
                preferences.categories.length + preferences.customRules.length <
                    64
                ? _addCustomRule
                : null,
            icon: const Icon(Icons.add),
            label: const Text('Add a custom rule'),
          ),
        ],
      ),
    );
  }
}

class _CustomRuleDialog extends StatefulWidget {
  const _CustomRuleDialog();

  @override
  State<_CustomRuleDialog> createState() => _CustomRuleDialogState();
}

class _CustomRuleDialogState extends State<_CustomRuleDialog> {
  final _input = TextEditingController();
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add a custom rule'),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _input,
        autofocus: true,
        maxLines: 4,
        maxLength: 512,
        decoration: const InputDecoration(
          hintText: 'Keep launch dates private.',
          helperText: 'Up to 512 UTF-8 bytes. Requires model support.',
        ),
        validator: (value) {
          final text = value?.trim() ?? '';
          if (text.isEmpty) return 'Enter a rule.';
          if (utf8.encode(text).length > 512) {
            return 'Use at most 512 UTF-8 bytes.';
          }
          return null;
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _input.text.trim());
          }
        },
        child: const Text('Add rule'),
      ),
    ],
  );
}
