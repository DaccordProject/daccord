import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/admin/utils/upload_budgets.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Instance-admin "Settings" tab: server-wide configuration (name, registration
/// policy, limits, MOTD, public listing, Terms of Service). Mirrors the
/// reference `server_management_panel` Settings page. Uses
/// `client.adminApi.getSettings` / `updateSettings`.
class AdminSettingsTab extends ConsumerStatefulWidget {
  const AdminSettingsTab({super.key});

  @override
  ConsumerState<AdminSettingsTab> createState() => _AdminSettingsTabState();
}

const _policies = ['open', 'invite_only', 'closed'];

class _AdminSettingsTabState extends ConsumerState<AdminSettingsTab> {
  final _serverName = TextEditingController();
  final _motd = TextEditingController();
  final _maxSpaces = TextEditingController();
  final _maxMembers = TextEditingController();
  final _tosText = TextEditingController();
  final _tosUrl = TextEditingController();

  /// Per-user upload budgets (`upload_requests_per_minute`,
  /// `upload_bytes_per_minute` shown as MB). Only offered — and only sent
  /// back — when the server reported them, so an older server that doesn't
  /// know the keys is neither shown controls it can't honour nor sent
  /// settings it would reject.
  final _uploadRequests = TextEditingController();
  final _uploadMb = TextEditingController();
  bool _hasUploadBudgets = false;

  String _policy = 'open';
  bool _publicListing = false;
  bool _tosEnabled = false;
  int _tosVersion = 1;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  AccordClient? get _client => ref.accordClient;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _serverName.dispose();
    _motd.dispose();
    _maxSpaces.dispose();
    _maxMembers.dispose();
    _tosText.dispose();
    _tosUrl.dispose();
    _uploadRequests.dispose();
    _uploadMb.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await client.adminApi.getSettings();
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _loading = false;
        _error = result.errorOr('Failed to load settings');
      });
      return;
    }
    final data = result.data;
    final d = data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
    setState(() {
      _loading = false;
      _serverName.text = d['server_name']?.toString() ?? '';
      final policy = d['registration_policy']?.toString() ?? 'open';
      _policy = _policies.contains(policy) ? policy : 'open';
      _maxSpaces.text = (d['max_spaces'] ?? 0).toString();
      _maxMembers.text = (d['max_members_per_space'] ?? 0).toString();
      _motd.text = d['motd']?.toString() ?? '';
      _publicListing = d['public_listing'] == true;
      _tosEnabled = d['tos_enabled'] == true;
      _tosText.text = d['tos_text']?.toString() ?? '';
      _tosUrl.text = d['tos_url']?.toString() ?? '';
      _tosVersion = asInt(d['tos_version'], 1);
      _hasUploadBudgets = d.containsKey('upload_requests_per_minute') ||
          d.containsKey('upload_bytes_per_minute');
      _uploadRequests.text = d['upload_requests_per_minute']?.toString() ?? '';
      final uploadBytes = asInt(d['upload_bytes_per_minute']);
      _uploadMb.text =
          uploadBytes > 0 ? formatUploadMbPerMinute(uploadBytes) : '';
    });
  }

  Future<void> _save() async {
    final client = _client;
    if (client == null) return;
    // Validate the upload budgets before anything is sent: the server rejects
    // an out-of-range value, and a rejected PATCH would drop every other
    // change on this form with it.
    int? uploadRequests;
    int? uploadBytes;
    if (_hasUploadBudgets) {
      uploadRequests = parseUploadRequestsPerMinute(_uploadRequests.text);
      uploadBytes = parseUploadMbPerMinute(_uploadMb.text);
      if (uploadRequests == null) {
        setState(() => _error = 'Uploads per minute must be a whole number '
            'from $kMinUploadRequestsPerMinute to '
            '$kMaxUploadRequestsPerMinute.');
        return;
      }
      if (uploadBytes == null) {
        setState(() => _error = 'Upload MB per minute must be more than 0 '
            'and at most ${formatUploadMbPerMinute(kMaxUploadBytesPerMinute)} '
            'MB (1 TiB).');
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final tosText = _tosText.text.trim();
    final tosUrl = _tosUrl.text.trim();
    final result = await client.adminApi.updateSettings({
      'server_name': _serverName.text.trim(),
      'registration_policy': _policy,
      'max_spaces': int.tryParse(_maxSpaces.text.trim()) ?? 0,
      'max_members_per_space': int.tryParse(_maxMembers.text.trim()) ?? 0,
      'motd': _motd.text.trim(),
      'public_listing': _publicListing,
      'tos_enabled': _tosEnabled,
      'tos_text': tosText.isEmpty ? null : tosText,
      'tos_url': tosUrl.isEmpty ? null : tosUrl,
      if (_hasUploadBudgets) ...{
        'upload_requests_per_minute': uploadRequests,
        'upload_bytes_per_minute': uploadBytes,
      },
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (!result.ok) {
      setState(() =>
          _error = result.errorOr('Failed to save settings'));
      return;
    }
    showInfoSnack(context, 'Server settings saved');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    if (_loading) {
      return const LoadingView();
    }
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InlineError(_error!, centered: false),
                ),
              _Label('Server name'),
              TextField(
                controller: _serverName,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Accord Server',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              _Label('Registration policy'),
              DropdownButtonFormField<String>(
                initialValue: _policy,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'open', child: Text('Open')),
                  DropdownMenuItem(
                      value: 'invite_only', child: Text('Invite only')),
                  DropdownMenuItem(value: 'closed', child: Text('Closed')),
                ],
                onChanged: (v) => setState(() => _policy = v ?? _policy),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Label('Max spaces (0 = ∞)'),
                        TextField(
                          controller: _maxSpaces,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Label('Max members/space (0 = ∞)'),
                        TextField(
                          controller: _maxMembers,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_hasUploadBudgets) ...[
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Label(
                            'Uploads per user per minute '
                            '($kMinUploadRequestsPerMinute–'
                            '$kMaxUploadRequestsPerMinute)',
                          ),
                          TextField(
                            controller: _uploadRequests,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Label('Upload MB per user per minute'),
                          TextField(
                            controller: _uploadMb,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                              suffixText: 'MB',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Per-user budgets for message sends with attachments, across '
                  'all channels and DMs — moderators and admins included. Text '
                  "messages don't count. Keep the MB budget at least as large "
                  'as the biggest single upload you allow.',
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: colors.gray,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _Label('Message of the day'),
              TextField(
                controller: _motd,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Shown to users on login',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('List on public server directory'),
                value: _publicListing,
                onChanged: (v) => setState(() => _publicListing = v),
              ),
              const Divider(height: 24),
              Text('Terms of Service',
                  style: theme.textTheme.titleSmall),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Require ToS acceptance during registration'),
                value: _tosEnabled,
                onChanged: (v) => setState(() => _tosEnabled = v),
              ),
              Text('Current version: $_tosVersion',
                  style: theme.textTheme.bodySmall!
                      .copyWith(color: colors.gray)),
              const SizedBox(height: 12),
              _Label('ToS text (markdown)'),
              TextField(
                controller: _tosText,
                minLines: 4,
                maxLines: 10,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Enter Terms of Service text…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              _Label('ToS external URL (optional)'),
              TextField(
                controller: _tosUrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'https://example.com/tos',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving ? null : _load,
                  child: const Text('Reset'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save settings'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context)
            .textTheme
            .labelSmall!
            .copyWith(color: colors.gray, letterSpacing: 0.6),
      ),
    );
  }
}
