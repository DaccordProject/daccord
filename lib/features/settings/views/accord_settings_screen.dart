import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/developer/views/developer_settings_page.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/profiles/views/profiles_page.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/settings/views/connections_settings_page.dart';
import 'package:bonfire/features/settings/views/privacy_settings_page.dart';
import 'package:bonfire/features/settings/views/settings_backup.dart';
import 'package:bonfire/features/error_reporting/controllers/error_reporting.dart';
import 'package:bonfire/features/updates/views/updates_page.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/user/views/accord_profile_edit.dart';
import 'package:bonfire/shared/app_info.dart';
import 'package:bonfire/features/voice/views/voice_settings_screen.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:universal_platform/universal_platform.dart';

/// Client settings: appearance (theme preset + accent), notifications, account.
class AccordSettingsScreen extends ConsumerWidget {
  const AccordSettingsScreen({super.key});

  static const _accentSwatches = <(int, String)>[
    (0xFF2448BE, 'Blue'),
    (0xFF5865F2, 'Blurple'),
    (0xFF57F287, 'Green'),
    (0xFFEB459E, 'Pink'),
    (0xFFFEE75C, 'Yellow'),
    (0xFFED4245, 'Red'),
    (0xFF88C0D0, 'Cyan'),
    (0xFFFF7A45, 'Orange'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final session = ref.watch(
      accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.session : null,
      ),
    );

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.foreground,
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/spaces'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader('Appearance'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in AppThemePreset.values)
                  ChoiceChip(
                    label: Text(preset.label),
                    selected: settings.themePreset == preset,
                    onSelected: (_) => controller.setThemePreset(preset),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              'Accent colour',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _AccentSwatch(
                  color: defaultAccentFor(settings.themePreset),
                  selected: settings.accentColor == null,
                  label: 'Default',
                  onTap: () => controller.setAccentColor(null),
                ),
                for (final (argb, name) in _accentSwatches)
                  _AccentSwatch(
                    color: Color(argb),
                    selected: settings.accentColor == argb,
                    label: name,
                    onTap: () => controller.setAccentColor(argb),
                  ),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('Compact mode'),
            subtitle: const Text('Denser message layout (smaller spacing)'),
            value: settings.compactMode,
            onChanged: controller.setCompactMode,
          ),
          SwitchListTile(
            title: const Text('Reduced motion'),
            subtitle: const Text('Minimise UI animations'),
            value: settings.reducedMotion,
            onChanged: controller.setReducedMotion,
          ),
          ListTile(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('UI scale'),
                Text('${(settings.uiScale * 100).round()}%'),
              ],
            ),
            subtitle: Slider(
              value: settings.uiScale.clamp(
                AccordSettings.minUiScale,
                AccordSettings.maxUiScale,
              ),
              min: AccordSettings.minUiScale,
              max: AccordSettings.maxUiScale,
              divisions:
                  ((AccordSettings.maxUiScale - AccordSettings.minUiScale) /
                          0.1)
                      .round(),
              label: '${(settings.uiScale * 100).round()}%',
              onChanged: controller.setUiScale,
            ),
          ),
          const Divider(height: 24),
          _SectionHeader('Notifications'),
          SwitchListTile(
            title: const Text('Enable notifications'),
            subtitle: const Text('Show a system notification when mentioned'),
            value: settings.notificationsEnabled,
            onChanged: controller.setNotificationsEnabled,
          ),
          SwitchListTile(
            title: const Text('Suppress @everyone'),
            subtitle: const Text('Never notify for @everyone / @here mentions'),
            value: settings.suppressEveryone,
            onChanged: settings.notificationsEnabled
                ? controller.setSuppressEveryone
                : null,
          ),
          if (UniversalPlatform.isAndroid)
            SwitchListTile(
              title: const Text('Background connection'),
              subtitle: const Text(
                'Stay connected while the app is in the background so '
                'messages and notifications keep arriving. Shows a '
                'persistent notification and uses more battery.',
              ),
              value: settings.backgroundConnection,
              onChanged: controller.setBackgroundConnection,
            ),
          const Divider(height: 24),
          _SectionHeader('Error Reporting'),
          SwitchListTile(
            title: const Text('Send error reports'),
            subtitle: const Text(
              'Anonymous crash and error reports. No personal data or '
              'message content is included',
            ),
            value: settings.errorReportingEnabled,
            onChanged: controller.setErrorReportingEnabled,
          ),
          ListTile(
            leading: Icon(Icons.bug_report_outlined, color: colors.dirtyWhite),
            title: const Text('Report a problem'),
            subtitle: const Text(
              'Describe a bug and send it to the developers',
            ),
            trailing: const Icon(Icons.chevron_right),
            enabled: settings.errorReportingEnabled,
            onTap: settings.errorReportingEnabled
                ? () => _showReportProblemDialog(context, ref)
                : null,
          ),
          const Divider(height: 24),
          _SectionHeader('Sounds'),
          SwitchListTile(
            title: const Text('Enable sounds'),
            subtitle: const Text('Play SFX for messages and mentions'),
            value: settings.soundsEnabled,
            onChanged: controller.setSoundsEnabled,
          ),
          ListTile(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Volume'),
                Text('${(settings.sfxVolume * 100).round()}%'),
              ],
            ),
            subtitle: Slider(
              value: settings.sfxVolume,
              onChanged: settings.soundsEnabled
                  ? controller.setSfxVolume
                  : null,
            ),
          ),
          const Divider(height: 24),
          _SectionHeader('Voice & Video'),
          ListTile(
            leading: Icon(Icons.mic_none, color: colors.dirtyWhite),
            title: const Text('Voice & video settings'),
            subtitle: const Text(
              'Microphone, speaker, sensitivity, camera, mic test',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showVoiceSettings(context),
          ),
          const Divider(height: 24),
          _SectionHeader('Account'),
          if (session != null)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: colors.primary,
                child: Text(
                  (session.username.isNotEmpty ? session.username[0] : '?')
                      .toUpperCase(),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              title: Text(session.username),
              subtitle: Text(session.server.baseUrl),
            ),
          ListTile(
            leading: Icon(Icons.edit_outlined, color: colors.dirtyWhite),
            title: const Text('Edit profile'),
            subtitle: const Text('Display name, bio, avatar'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showAccordProfileEdit(context),
          ),
          if (ref.watch(connectionsControllerProvider).hasMultiple)
            ListTile(
              leading: Icon(Icons.dns_outlined, color: colors.dirtyWhite),
              title: const Text('Per-server profile'),
              subtitle: const Text("Override name/bio/avatar on one server"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickServerProfile(context, ref),
            ),
          ListTile(
            leading: Icon(Icons.switch_account, color: colors.dirtyWhite),
            title: const Text('Switch account'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/switcher'),
          ),
          ListTile(
            leading: Icon(Icons.devices, color: colors.dirtyWhite),
            title: const Text('Device profiles'),
            subtitle: const Text('Isolated, PIN-lockable local profiles'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showProfilesSettings(context),
          ),
          ListTile(
            leading: Icon(Icons.link, color: colors.dirtyWhite),
            title: const Text('Connections'),
            subtitle: const Text('Linked third-party (OAuth) accounts'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showConnectionsSettings(context),
          ),
          ListTile(
            leading: Icon(Icons.privacy_tip_outlined, color: colors.dirtyWhite),
            title: const Text('Privacy & Data'),
            subtitle: const Text('Data export, leave & delete data, retention'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showPrivacySettings(context),
          ),
          if (session?.isAdmin ?? false)
            ListTile(
              leading: Icon(
                Icons.admin_panel_settings,
                color: colors.dirtyWhite,
              ),
              title: const Text('Server administration'),
              subtitle: const Text('Spaces, users, reports, settings'),
              onTap: () => context.go('/admin'),
            ),
          const Divider(height: 24),
          _SectionHeader('Server Directory'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: _MasterServerField(),
          ),
          const Divider(height: 24),
          _SectionHeader('Updates'),
          ListTile(
            leading: Icon(Icons.system_update, color: colors.dirtyWhite),
            title: const Text('Updates'),
            subtitle: const Text('Current version, check for new releases'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showUpdatesSettings(context),
          ),
          const Divider(height: 24),
          _SectionHeader('Backup'),
          const SettingsBackupSection(),
          const Divider(height: 24),
          _SectionHeader('Developer'),
          SwitchListTile(
            title: const Text('Developer Mode'),
            subtitle: const Text(
              'Unlock the local Client MCP server for AI agents',
            ),
            value: settings.developerMode,
            onChanged: controller.setDeveloperMode,
          ),
          if (settings.developerMode)
            ListTile(
              leading: Icon(Icons.terminal, color: colors.dirtyWhite),
              title: const Text('Client MCP server'),
              subtitle: const Text('Token, port, tool groups, activity'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showDeveloperSettings(context),
            ),
          const Divider(height: 24),
          _SectionHeader('About'),
          const ListTile(
            title: Text('Daccord'),
            subtitle: Text('A native multi-platform Daccord client (GPLv3).'),
            trailing: Text('v$kAppVersion'),
          ),
          const Divider(height: 24),
          ListTile(
            leading: Icon(Icons.logout, color: colors.red),
            title: Text('Log out', style: TextStyle(color: colors.red)),
            onTap: () {
              ref.read(accordAuthProvider.notifier).logout();
              if (context.mounted) context.go('/');
            },
          ),
        ],
      ),
    );
  }
}

/// User-initiated feedback, mirroring the reference client's "Report a
/// Problem" dialog: an optional free-text description sent as a tagged
/// `user-feedback` event through the opt-in error reporting pipeline.
Future<void> _showReportProblemDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final textController = TextEditingController();
  final send = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Report a Problem'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: textController,
            autofocus: true,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Describe what happened (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No personal data or message content is included.',
            style: Theme.of(ctx).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Send Report'),
        ),
      ],
    ),
  );
  if (send == true) {
    await ref
        .read(errorReportingControllerProvider.notifier)
        .reportProblem(textController.text.trim());
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Report sent. Thank you!')),
      );
    }
  }
  textController.dispose();
}

/// Lets the user pick which connected server's profile to edit, then opens the
/// per-server profile editor for it.
Future<void> _pickServerProfile(BuildContext context, WidgetRef ref) async {
  final connections = ref.read(connectionsControllerProvider).connections;
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final conn in connections)
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(
                conn.session.server.name ?? conn.session.server.baseUrl,
              ),
              subtitle: Text(conn.session.username),
              onTap: () {
                Navigator.of(ctx).pop();
                showAccordProfileEdit(context, serverKey: conn.key);
              },
            ),
        ],
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium!.copyWith(
          color: colors.gray,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Editable master-server directory URL (default https://master.daccord.gg),
/// used to browse public spaces without an account.
class _MasterServerField extends ConsumerStatefulWidget {
  const _MasterServerField();

  @override
  ConsumerState<_MasterServerField> createState() => _MasterServerFieldState();
}

class _MasterServerFieldState extends ConsumerState<_MasterServerField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(settingsControllerProvider).masterServerUrl,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    ref
        .read(settingsControllerProvider.notifier)
        .setMasterServerUrl(_controller.text);
    final applied = ref.read(settingsControllerProvider).masterServerUrl;
    _controller.text = applied;
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('Master server URL saved')));
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Master server URL',
              hintText: AccordSettings.defaultMasterServerUrl,
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _save(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
    this.label,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final checkColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.light
        ? Colors.black
        : Colors.white;
    final swatch = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? colors.dirtyWhite : Colors.transparent,
            width: 3,
          ),
        ),
        child: selected ? Icon(Icons.check, size: 18, color: checkColor) : null,
      ),
    );
    final label = this.label;
    if (label == null || label.isEmpty) return swatch;
    return Tooltip(message: label, child: swatch);
  }
}
