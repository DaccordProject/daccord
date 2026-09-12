import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/automod/utils/automod_policy.dart';
import 'package:flutter/material.dart';

Future<Map<String, dynamic>?> editAutomodRule(
  BuildContext context, {
  Map<String, dynamic>? rule,
  List<AccordChannel> channels = const [],
}) => showDialog<Map<String, dynamic>>(
  context: context,
  builder: (_) => _RuleEditor(rule: rule, channels: channels),
);

class _RuleEditor extends StatefulWidget {
  const _RuleEditor({this.rule, required this.channels});
  final Map<String, dynamic>? rule;
  final List<AccordChannel> channels;
  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _id;
  late final TextEditingController _categories;
  late final TextEditingController _threshold;
  late final TextEditingController _seconds;
  late final TextEditingController _accountAge;
  late final TextEditingController _spaceAge;
  late String _trigger, _action, _scope;
  late bool _requireRole;
  late Set<String> _channelIds;
  String? _error;
  @override
  void initState() {
    super.initState();
    final rule = widget.rule ?? <String, dynamic>{};
    final trigger = automodMap(rule['trigger']),
        action = automodMap(rule['action']),
        scope = automodMap(rule['scope']);
    _id = TextEditingController(text: asString(rule['id']));
    _trigger = asString(trigger['type'], 'media');
    _action = asString(action['type'], 'quarantine');
    _scope = asString(scope['type'], 'non_nsfw');
    _channelIds = automodList(scope['ids']).map((id) => id.toString()).toSet();
    _categories = TextEditingController(
      text: trigger['categories'] == null
          ? 'FEMALE_BREAST_EXPOSED, FEMALE_GENITALIA_EXPOSED, MALE_GENITALIA_EXPOSED, ANUS_EXPOSED'
          : automodList(trigger['categories']).join(', '),
    );
    _threshold = TextEditingController(text: '${trigger['threshold'] ?? 0.8}');
    _seconds = TextEditingController(text: '${action['seconds'] ?? 300}');
    _accountAge = TextEditingController(
      text: '${trigger['min_account_age_hours'] ?? 24}',
    );
    _spaceAge = TextEditingController(
      text: '${trigger['min_space_age_hours'] ?? 1}',
    );
    _requireRole = trigger['require_role'] == true;
  }

  @override
  void dispose() {
    for (final c in [
      _id,
      _categories,
      _threshold,
      _seconds,
      _accountAge,
      _spaceAge,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _number(
    TextEditingController controller,
    String label,
    int min,
    int max,
  ) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label),
    validator: (v) {
      final number = int.tryParse(v ?? '');
      return number == null || number < min || number > max
          ? 'Enter $min–$max.'
          : null;
    },
  );
  void _save() {
    if (!_form.currentState!.validate()) return;
    final rule = <String, dynamic>{
      'id': _id.text.trim(),
      'trigger': <String, dynamic>{
        'type': _trigger,
        if (_trigger == 'media') ...{
          'categories': _categories.text
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList(),
          'threshold': double.tryParse(_threshold.text),
        },
        if (_trigger == 'low_trust') ...{
          'min_account_age_hours': int.parse(_accountAge.text),
          'min_space_age_hours': int.parse(_spaceAge.text),
          'require_role': _requireRole,
        },
      },
      'scope': {
        'type': _scope,
        if (_scope == 'channels') 'ids': _channelIds.toList(),
      },
      'action': {
        'type': _action,
        if (_action == 'timeout') 'seconds': int.parse(_seconds.text),
      },
    };
    final error = validateAutomodPolicy({
      'retention_days': 7,
      'rules': [rule],
    });
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, rule);
  }

  @override
  Widget build(BuildContext context) {
    // Preserve newer rule types rather than silently rewriting them as defaults.
    if (!automodTriggers.containsKey(_trigger) ||
        !automodActions.containsKey(_action) ||
        !['all', 'non_nsfw', 'channels'].contains(_scope)) {
      return AlertDialog(
        title: const Text('Update required'),
        content: const Text('This rule uses options this client cannot edit.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    }
    return AlertDialog(
      title: Text(widget.rule == null ? 'Add rule' : 'Edit rule'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _id,
                  decoration: const InputDecoration(labelText: 'Rule name'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter a name.' : null,
                ),
                DropdownButtonFormField<String>(
                  initialValue: _trigger,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'When'),
                  items: [
                    for (final e in automodTriggers.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() {
                    _trigger = v!;
                    if (!automodAllowsTimeout(v) && _action == 'timeout') {
                      _action = 'quarantine';
                    }
                  }),
                ),
                if (_trigger == 'media') ...[
                  TextFormField(
                    controller: _categories,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Detector categories',
                      helperText:
                          'Comma-separated category names supported by the server detector.',
                    ),
                  ),
                  TextFormField(
                    controller: _threshold,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Threshold (0–1)',
                    ),
                  ),
                  const Text(
                    'Videos sample five frames at 10%, 30%, 50%, 70% and 90%. Content between samples can be missed.',
                  ),
                ],
                if (_trigger == 'low_trust') ...[
                  _number(
                    _accountAge,
                    'Minimum account age (hours)',
                    0,
                    4294967295,
                  ),
                  _number(
                    _spaceAge,
                    'Minimum membership age (hours)',
                    0,
                    4294967295,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Require an assigned role'),
                    value: _requireRole,
                    onChanged: (v) => setState(() => _requireRole = v),
                  ),
                ],
                DropdownButtonFormField<String>(
                  initialValue: _scope,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Channels'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All channels')),
                    DropdownMenuItem(
                      value: 'non_nsfw',
                      child: Text('Outside NSFW channels'),
                    ),
                    DropdownMenuItem(
                      value: 'channels',
                      child: Text('Selected channels'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _scope = v!),
                ),
                if (_scope == 'channels') ...[
                  if (widget.channels.isEmpty)
                    const Text(
                      'Open a space to load its channels before adding a channel-specific rule.',
                    ),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final channel in widget.channels)
                        FilterChip(
                          label: Text(channel.name ?? channel.id),
                          selected: _channelIds.contains(channel.id),
                          onSelected: (v) => setState(() {
                            if (v) {
                              _channelIds.add(channel.id);
                            } else {
                              _channelIds.remove(channel.id);
                            }
                          }),
                        ),
                    ],
                  ),
                  for (final id in _channelIds.where(
                    (id) => !widget.channels.any((c) => c.id == id),
                  ))
                    InputChip(
                      label: Text('Channel $id'),
                      onDeleted: () => setState(() => _channelIds.remove(id)),
                    ),
                ],
                DropdownButtonFormField<String>(
                  key: ValueKey('action-$_trigger-$_action'),
                  initialValue: _action,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Action'),
                  items: [
                    for (final e in automodActions.entries)
                      if (e.key != 'timeout' || automodAllowsTimeout(_trigger))
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _action = v!),
                ),
                if (_action == 'timeout')
                  _number(_seconds, 'Timeout (seconds)', 1, 86400),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Use rule')),
      ],
    );
  }
}
