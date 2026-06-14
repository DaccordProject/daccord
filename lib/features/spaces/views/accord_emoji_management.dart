import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/responsive_dialog.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/messaging/controllers/accord_emojis.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the custom-emoji management dialog for [spaceId]. Gated on
/// `manage_emojis` at the call site (space settings). Lists existing custom
/// emoji with inline rename + delete, and an upload affordance for new ones.
/// Mirrors the reference client's emoji management dialog.
Future<void> showAccordEmojiManagement(
  BuildContext context, {
  required String spaceId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _EmojiManagement(spaceId: spaceId),
  );
}

class _EmojiManagement extends ConsumerStatefulWidget {
  const _EmojiManagement({required this.spaceId});

  final String spaceId;

  @override
  ConsumerState<_EmojiManagement> createState() => _EmojiManagementState();
}

class _EmojiManagementState extends ConsumerState<_EmojiManagement> {
  bool _busy = false;
  String? _error;

  AccordClient? get _client => ref.accordClient;

  Future<void> _pickAndUpload() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    if (file?.bytes == null) return;
    final client = _client;
    if (client == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final dataUri = AccordCDN.buildDataUri(file!.bytes!, file.name);
    // Drop the extension for a sensible default name; user can rename inline.
    final defaultName = _sanitizeName(file.name.split('.').first);
    final result = await client.emojis.create(widget.spaceId, {
      'name': defaultName,
      'image': dataUri,
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      setState(
        () => _error = result.error?.toString() ?? 'Failed to upload emoji',
      );
      return;
    }
    final emoji = result.data;
    if (emoji is AccordEmoji) {
      ref
          .read(accordEmojisControllerProvider(widget.spaceId).notifier)
          .upsert(emoji);
    }
  }

  Future<void> _rename(AccordEmoji emoji) async {
    final client = _client;
    if (client == null) return;
    final id = emoji.id;
    if (id == null) return;
    final next = await _promptForName(emoji.name);
    if (next == null || next == emoji.name) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await client.emojis.update(widget.spaceId, id, {
      'name': _sanitizeName(next),
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      setState(
        () => _error = result.error?.toString() ?? 'Failed to rename emoji',
      );
      return;
    }
    final updated = result.data;
    if (updated is AccordEmoji) {
      ref
          .read(accordEmojisControllerProvider(widget.spaceId).notifier)
          .upsert(updated);
    }
  }

  Future<void> _delete(AccordEmoji emoji) async {
    final client = _client;
    if (client == null) return;
    final id = emoji.id;
    if (id == null) return;
    final ok = await showConfirmDialog(
      context,
      title: 'Delete emoji?',
      message: ':${emoji.name}: will be removed from this space.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await client.emojis.delete(widget.spaceId, id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      setState(
        () => _error = result.error?.toString() ?? 'Failed to delete emoji',
      );
      return;
    }
    ref
        .read(accordEmojisControllerProvider(widget.spaceId).notifier)
        .remove(id);
  }

  Future<String?> _promptForName(String initial) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename emoji'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name',
            helperText: 'Letters, numbers, and underscores',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  static String _sanitizeName(String raw) {
    // Server-side rules typically require [a-z0-9_]; lowercase + replace
    // anything else with underscores so a freshly-uploaded emoji has a valid
    // default name. Falls back to "emoji" if everything got stripped.
    final cleaned = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return cleaned.isEmpty ? 'emoji' : cleaned;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final emojis = ref.watch(accordEmojisControllerProvider(widget.spaceId));
    final cdnUrl = ref.watch(
      accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.session.server.cdnUrl : null,
      ),
    );

    return Dialog(
      child: ConstrainedBox(
        constraints: dialogConstraints(context, maxWidth: 480, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.emoji_emotions_outlined,
                    size: 18,
                    color: colors.dirtyWhite,
                  ),
                  const SizedBox(width: 8),
                  Text('Custom emoji', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy ? null : _pickAndUpload,
                icon: const Icon(Icons.upload, size: 18),
                label: const Text('Upload emoji'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall!.copyWith(color: colors.red),
                ),
              ],
              const SizedBox(height: 12),
              Flexible(
                child: emojis == null
                    ? const Center(child: CircularProgressIndicator())
                    : emojis.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'No custom emoji yet.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: emojis.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final emoji = emojis[index];
                          final url = _emojiUrl(emoji, cdnUrl);
                          return ListTile(
                            leading: url == null
                                ? const Icon(Icons.image_outlined)
                                : CachedNetworkImage(
                                    imageUrl: url,
                                    width: 28,
                                    height: 28,
                                    errorWidget: (_, _, _) =>
                                        const Icon(Icons.broken_image),
                                  ),
                            title: Text(
                              ':${emoji.name}:',
                              style: theme.textTheme.titleSmall,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Rename',
                                  onPressed: _busy
                                      ? null
                                      : () => _rename(emoji),
                                  icon: const Icon(Icons.edit, size: 18),
                                ),
                                IconButton(
                                  tooltip: 'Delete',
                                  onPressed: _busy
                                      ? null
                                      : () => _delete(emoji),
                                  icon: Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: colors.red,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _emojiUrl(AccordEmoji emoji, String? cdnUrl) {
    if (emoji.imageUrl.isNotEmpty) {
      return AccordCDN.resolvePath(emoji.imageUrl, cdnUrl: cdnUrl ?? '');
    }
    final id = emoji.id;
    if (id == null) return null;
    return AccordCDN.emoji(
      id,
      format: emoji.animated ? 'gif' : 'png',
      cdnUrl: cdnUrl ?? '',
    );
  }
}
