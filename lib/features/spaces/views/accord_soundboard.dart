import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
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

class _SoundboardDialogState extends ConsumerState<_SoundboardDialog> {
  List<AccordSound>? _sounds;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  AccordClient? get _client => ref.read(accordAuthProvider
      .select((s) => s is AccordAuthLoggedIn ? s.client : null));

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    final result = await client.soundboard.list(widget.spaceId);
    if (!mounted) return;
    final data = result.data;
    setState(() {
      _sounds = result.ok && data is List
          ? data.whereType<AccordSound>().toList()
          : <AccordSound>[];
    });
  }

  Future<void> _play(AccordSound sound) async {
    final client = _client;
    final id = sound.id;
    if (client == null || id == null) return;
    final result = await client.soundboard.play(widget.spaceId, id);
    if (!mounted || result.ok) return;
    setState(() => _error = 'Failed to play (join a voice channel first)');
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
      _error = null;
    });
    final result = await client.soundboard
        .create(widget.spaceId, {'name': name, 'audio': dataUri});
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.ok) {
      await _load();
    } else {
      setState(() => _error = 'Failed to add sound');
    }
  }

  Future<void> _delete(AccordSound sound) async {
    final client = _client;
    final id = sound.id;
    if (client == null || id == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await client.soundboard.delete(widget.spaceId, id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.ok) {
      setState(() => _sounds =
          (_sounds ?? const []).where((s) => s.id != id).toList());
    } else {
      setState(() => _error = 'Failed to remove sound');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final sounds = _sounds;
    return Dialog(
      backgroundColor: colors.foreground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
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
                    child: Text('Soundboard',
                        style: theme.textTheme.titleMedium),
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
              const SizedBox(height: 12),
              Flexible(
                child: sounds == null
                    ? const Center(child: CircularProgressIndicator())
                    : sounds.isEmpty
                        ? Center(
                            child: Text('No sounds yet',
                                style: theme.textTheme.bodyMedium))
                        : GridView.count(
                            crossAxisCount: 3,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 1.1,
                            shrinkWrap: true,
                            children: [
                              for (final sound in sounds)
                                _SoundTile(
                                  sound: sound,
                                  canManage: widget.canManage,
                                  onPlay: () => _play(sound),
                                  onDelete: () => _delete(sound),
                                ),
                            ],
                          ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: theme.textTheme.bodySmall!
                        .copyWith(color: colors.red)),
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
  });

  final AccordSound sound;
  final bool canManage;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

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
                  Icon(Icons.play_circle_fill,
                      size: 32, color: colors.primary),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(sound.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            ),
            if (canManage)
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Remove',
                  onPressed: onDelete,
                  icon: Icon(Icons.close, color: colors.gray),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
