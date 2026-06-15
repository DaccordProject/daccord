import 'package:bonfire/features/developer/controllers/mcp_server_controller.dart';
import 'package:bonfire/shared/components/settings_scaffold.dart';
import 'package:bonfire/shared/components/section_header.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pushes the Developer / Client MCP settings page.
Future<void> showDeveloperSettings(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const DeveloperSettingsPage()),
  );
}

/// Controls the local Client MCP server: enable toggle, bearer token
/// (generate/copy/rotate), port, exposed tool groups, live status, and a
/// recent-activity log. Mirrors the reference client's developer panel.
class DeveloperSettingsPage extends ConsumerWidget {
  const DeveloperSettingsPage({super.key});

  static const _groupLabels = <String, String>{
    'read': 'Read (state, spaces, channels, messages)',
    'navigate': 'Navigate (switch space/channel, open views)',
    'message': 'Message (send, edit, delete, react)',
    'moderate': 'Moderate (kick, ban, timeout)',
    'manage': 'Manage (roles, permissions, member roles)',
    'voice': 'Voice (join, leave, mute, deafen)',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final server = ref.watch(mcpServerControllerProvider);

    return SettingsScaffold(
      title: 'Developer',
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          SectionHeader('Client MCP server'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Exposes a local Model Context Protocol server on '
              '127.0.0.1 so AI agents on this machine can read state and '
              'drive the app. Bound to loopback only and protected by a '
              'bearer token that never leaves this device.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colors.gray),
            ),
          ),
          SwitchListTile(
            title: const Text('Enable MCP server'),
            subtitle: Text(server.listening
                ? 'Listening on 127.0.0.1:${server.port}'
                : 'Stopped'),
            value: settings.mcpEnabled,
            onChanged: (v) => controller.setMcpEnabled(v),
          ),
          if (settings.mcpEnabled) ...[
            const _PortField(),
            const _TokenTile(),
            const Divider(height: 24),
            SectionHeader('Exposed tool groups'),
            for (final group in AccordSettings.mcpToolGroups)
              CheckboxListTile(
                dense: true,
                title: Text(_groupLabels[group] ?? group),
                value: settings.mcpAllowedGroups.contains(group),
                onChanged: (v) =>
                    controller.setMcpGroupAllowed(group, v ?? false),
              ),
            const Divider(height: 24),
            SectionHeader(
              'Recent activity',
              trailing: TextButton(
                onPressed: () => ref
                    .read(mcpServerControllerProvider.notifier)
                    .clearActivity(),
                child: const Text('Clear'),
              ),
            ),
            if (server.activity.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text('No tool calls yet.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: colors.gray)),
              )
            else
              for (final entry in server.activity.reversed)
                ListTile(
                  dense: true,
                  leading: Icon(
                    entry.ok ? Icons.check_circle : Icons.error,
                    color: entry.ok ? colors.green : colors.red,
                    size: 18,
                  ),
                  title: Text(entry.tool),
                  trailing: Text(
                    _formatTime(entry.time),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: colors.gray),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  static String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}

class _PortField extends ConsumerStatefulWidget {
  const _PortField();

  @override
  ConsumerState<_PortField> createState() => _PortFieldState();
}

class _PortFieldState extends ConsumerState<_PortField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(settingsControllerProvider).mcpPort.toString(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed != null) {
      ref.read(settingsControllerProvider.notifier).setMcpPort(parsed);
    }
    final applied = ref.read(settingsControllerProvider).mcpPort;
    _controller.text = applied.toString();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Port',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _save(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}

class _TokenTile extends ConsumerWidget {
  const _TokenTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final token = ref.watch(
        settingsControllerProvider.select((s) => s.mcpToken));
    final masked = token.isEmpty
        ? '(none)'
        : '${token.substring(0, 8)}…${token.substring(token.length - 4)}';
    return ListTile(
      title: const Text('Bearer token'),
      subtitle: Text(masked,
          style: TextStyle(fontFamily: 'monospace', color: colors.gray)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy, size: 18),
            onPressed: token.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: token));
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      const SnackBar(content: Text('Token copied')),
                    );
                  },
          ),
          IconButton(
            tooltip: 'Regenerate',
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: () => ref
                .read(settingsControllerProvider.notifier)
                .regenerateMcpToken(),
          ),
        ],
      ),
    );
  }
}
