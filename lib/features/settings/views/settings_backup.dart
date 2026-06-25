import 'dart:convert';
import 'dart:typed_data';

import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Export / import of the local client settings (theme, notifications, voice,
/// etc.) as a JSON file. Ports the reference client's profile export/import
/// (`config_export.gd`); secrets (the local MCP token) are stripped on export
/// and never overwritten on import.
class SettingsBackupSection extends ConsumerWidget {
  const SettingsBackupSection({super.key});

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final json = ref.read(settingsControllerProvider.notifier).exportJson();
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(json)),
    );
    String? path;
    try {
      path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export settings',
        fileName: 'daccord-settings.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: bytes,
      );
    } catch (_) {
      if (context.mounted) _toast(context, 'Could not save the settings file.');
      return;
    }
    if (path != null && context.mounted) _toast(context, 'Settings exported.');
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        dialogTitle: 'Import settings',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
    } catch (_) {
      if (context.mounted) _toast(context, 'Could not open the settings file.');
      return;
    }
    if (picked == null || picked.files.isEmpty) return; // cancelled
    final bytes = picked.files.first.bytes;
    if (bytes == null) return;
    Map<dynamic, dynamic>? map;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map) map = decoded;
    } catch (_) {
      map = null;
    }
    if (map == null) {
      if (context.mounted) {
        _toast(context, 'That file is not a valid settings export.');
      }
      return;
    }
    final ok = ref.read(settingsControllerProvider.notifier).importJson(map);
    if (context.mounted) {
      _toast(context, ok ? 'Settings imported.' : 'Could not import settings.');
    }
  }

  void _toast(BuildContext context, String message) {
    if (!context.mounted) return;
    showInfoSnack(context, message);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    return Column(
      children: [
        ListTile(
          leading: Icon(Icons.upload_file, color: colors.dirtyWhite),
          title: const Text('Export settings'),
          subtitle: const Text('Save your preferences to a JSON file'),
          onTap: () => _export(context, ref),
        ),
        ListTile(
          leading: Icon(
            Icons.download_for_offline_outlined,
            color: colors.dirtyWhite,
          ),
          title: const Text('Import settings'),
          subtitle: const Text('Restore preferences from a JSON file'),
          onTap: () => _import(context, ref),
        ),
      ],
    );
  }
}
