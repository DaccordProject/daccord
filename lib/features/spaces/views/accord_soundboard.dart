import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/responsive_dialog.dart';
import 'package:bonfire/shared/utils/self_loading_list.dart';
import 'package:bonfire/shared/utils/text_prompt_dialog.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the soundboard for [spaceId]: a grid of sounds with play buttons, plus
/// add/remove controls when [canManage] is set. Playback is triggered
/// server-side (the sound plays into the active voice channel) — this client
/// only fires the play request.
Future<void> showAccordSoundboard(
  BuildContext context, {
  required String spaceId,
  required bool canManage,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _SoundboardDialog(spaceId: spaceId, canManage: canManage),
  );
}

class _SoundboardDialog extends ConsumerStatefulWidget {
  const _SoundboardDialog({required this.spaceId, required this.canManage});

  final String spaceId;
  final bool canManage;

  @override
  ConsumerState<_SoundboardDialog> createState() => _SoundboardDialogState();
}

class _SoundboardDialogState extends ConsumerState<_SoundboardDialog>
    with SelfLoadingListState<AccordSound, _SoundboardDialog> {
  bool _busy = false;
  String _query = '';

  AccordClient? get _client => ref.accordClient;

  @override
  bool get canLoad => _client != null;

  @override
  Future<(List<AccordSound>? items, String? error)> fetchItems() async {
    final result = await _client!.soundboard.list(widget.spaceId);
    final data = result.data;
    return (
      result.ok && data is List
          ? data.whereType<AccordSound>().toList()
          : <AccordSound>[],
      null,
    );
  }

  Future<void> _play(AccordSound sound) async {
    final client = _client;
    final id = sound.id;
    if (client == null || id == null) return;
    final result = await client.soundboard.play(widget.spaceId, id);
    if (!mounted || result.ok) return;
    setState(() => error = 'Failed to play (join a voice channel first)');
  }

  Future<void> _add() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    if (file?.bytes == null) return;
    final name = file!.name.split('.').first;
    final dataUri = AccordCDN.buildDataUri(file.bytes!, file.name);
    final client = _client;
    if (client == null) return;
    setState(() {
      _busy = true;
      error = null;
    });
    final result = await client.soundboard.create(widget.spaceId, {
      'name': name,
      'audio': dataUri,
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.ok) {
      await load();
    } else {
      setState(() => error = 'Failed to add sound');
    }
  }

  Future<void> _rename(AccordSound sound) async {
    final id = sound.id;
    final client = _client;
    if (id == null || client == null) return;
    final name = (await showTextPromptDialog(
      context,
      title: 'Rename sound',
      initial: sound.name,
    ))?.trim();
    if (name == null || name.isEmpty || name == sound.name || !mounted) return;
    final result = await client.soundboard.update(widget.spaceId, id, {
      'name': name,
    });
    if (!mounted) return;
    if (result.ok) {
      setState(() => sound.name = name);
    } else {
      setState(() => error = 'Failed to rename sound');
    }
  }

  Future<void> _setVolume(AccordSound sound) async {
    final id = sound.id;
    final client = _client;
    if (id == null || client == null) return;
    final volume = await showDialog<double>(
      context: context,
      builder: (ctx) => _VolumeDialog(initial: sound.volume),
    );
    if (volume == null || volume == sound.volume || !mounted) return;
    final result = await client.soundboard.update(widget.spaceId, id, {
      'volume': volume,
    });
    if (!mounted) return;
    if (result.ok) {
      setState(() => sound.volume = volume);
    } else {
      setState(() => error = 'Failed to set volume');
    }
  }

  Future<void> _delete(AccordSound sound) async {
    final client = _client;
    final id = sound.id;
    if (client == null || id == null) return;
    setState(() {
      _busy = true;
      error = null;
    });
    final result = await client.soundboard.delete(widget.spaceId, id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.ok) {
      setState(
        () => items = (items ?? const []).where((s) => s.id != id).toList(),
      );
    } else {
      setState(() => error = 'Failed to remove sound');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final sounds = items;
    return Dialog(
      backgroundColor: colors.foreground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: dialogConstraints(context, maxWidth: 480, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.graphic_eq, size: 20, color: colors.dirtyWhite),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Soundboard',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (widget.canManage)
                    IconButton(
                      tooltip: 'Add sound',
                      onPressed: _busy ? null : _add,
                      icon: Icon(Icons.add, size: 20, color: colors.dirtyWhite),
                    ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, size: 20, color: colors.gray),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (sounds != null && sounds.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    onChanged: (v) =>
                        setState(() => _query = v.trim().toLowerCase()),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: colors.darkGray,
                      prefixIcon: Icon(
                        Icons.search,
                        size: 18,
                        color: colors.gray,
                      ),
                      hintText: 'Search sounds',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              Flexible(
                child: sounds == null
                    ? const LoadingView()
                    : Builder(
                        builder: (context) {
                          final filtered = _query.isEmpty
                              ? sounds
                              : sounds
                                    .where(
                                      (s) =>
                                          s.name.toLowerCase().contains(_query),
                                    )
                                    .toList();
                          if (sounds.isEmpty) {
                            return Center(
                              child: Text(
                                'No sounds yet',
                                style: theme.textTheme.bodyMedium,
                              ),
                            );
                          }
                          if (filtered.isEmpty) {
                            return Center(
                              child: Text(
                                'No matches',
                                style: theme.textTheme.bodyMedium,
                              ),
                            );
                          }
                          return GridView.count(
                            crossAxisCount: 3,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 1.1,
                            shrinkWrap: true,
                            children: [
                              for (final sound in filtered)
                                _SoundTile(
                                  sound: sound,
                                  canManage: widget.canManage,
                                  onPlay: () => _play(sound),
                                  onDelete: () => _delete(sound),
                                  onRename: () => _rename(sound),
                                  onVolume: () => _setVolume(sound),
                                ),
                            ],
                          );
                        },
                      ),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                InlineError(error!, centered: false),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SoundTile extends StatelessWidget {
  const _SoundTile({
    required this.sound,
    required this.canManage,
    required this.onPlay,
    required this.onDelete,
    required this.onRename,
    required this.onVolume,
  });

  final AccordSound sound;
  final bool canManage;
  final VoidCallback onPlay;
  final VoidCallback onDelete;
  final VoidCallback onRename;
  final VoidCallback onVolume;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Material(
      color: colors.darkGray,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPlay,
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_circle_fill, size: 32, color: colors.primary),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      sound.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            if (canManage)
              Positioned(
                top: 0,
                right: 0,
                child: PopupMenuButton<String>(
                  iconSize: 16,
                  tooltip: 'Manage',
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.more_vert, color: colors.gray),
                  onSelected: (v) {
                    switch (v) {
                      case 'rename':
                        onRename();
                      case 'volume':
                        onVolume();
                      case 'delete':
                        onDelete();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'volume', child: Text('Volume')),
                    PopupMenuItem(value: 'delete', child: Text('Remove')),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A 0–200% volume slider for a soundboard sound (stored as a 0.0–2.0 gain;
/// 1.0 = 100%). Returns the chosen gain, or null if cancelled.
class _VolumeDialog extends StatefulWidget {
  const _VolumeDialog({required this.initial});

  final double initial;

  @override
  State<_VolumeDialog> createState() => _VolumeDialogState();
}

class _VolumeDialogState extends State<_VolumeDialog> {
  late double _value = widget.initial.clamp(0.0, 2.0);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sound volume'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${(_value * 100).round()}%'),
          Slider(
            value: _value,
            max: 2.0,
            divisions: 20,
            label: '${(_value * 100).round()}%',
            onChanged: (v) => setState(() => _value = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_value),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
