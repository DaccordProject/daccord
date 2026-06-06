import 'dart:typed_data';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the self-profile editor (display name, bio, avatar). Mirrors the
/// reference client's editable profile card. Calls `users.updateMe` and
/// updates the global user cache so the change is visible everywhere the
/// current user is rendered.
Future<void> showAccordProfileEdit(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _ProfileEdit(),
  );
}

class _ProfileEdit extends ConsumerStatefulWidget {
  const _ProfileEdit();

  @override
  ConsumerState<_ProfileEdit> createState() => _ProfileEditState();
}

class _ProfileEditState extends ConsumerState<_ProfileEdit> {
  final _displayName = TextEditingController();
  final _bio = TextEditingController();
  bool _busy = false;
  bool _loaded = false;
  String? _error;

  /// Bytes of a freshly-picked avatar awaiting save. When non-null, save uses
  /// it as a data URI; otherwise the current server-side avatar is unchanged.
  List<int>? _newAvatarBytes;
  String? _newAvatarFilename;

  /// The chosen imageless-avatar background color (stored as the user's
  /// `accent_color`). `null` means "transparent" — the avatar falls back to the
  /// deterministic [accordAvatarColor] derived from the user ID.
  int? _accentColor;

  /// Preset background swatches for the imageless avatar.
  static const _avatarSwatches = <int>[
    0xFF2448BE, // blue
    0xFF5865F2, // blurple
    0xFF57F287, // green
    0xFFEB459E, // pink
    0xFFFEE75C, // yellow
    0xFFED4245, // red
    0xFF88C0D0, // cyan
    0xFFFF7A45, // orange
  ];

  AccordClient? get _client => ref.read(
        accordAuthProvider
            .select((s) => s is AccordAuthLoggedIn ? s.client : null),
      );

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _displayName.dispose();
    _bio.dispose();
    super.dispose();
  }

  /// Pulls the current profile via `users.getMe` (the cached session only
  /// carries name+avatar, not bio). Falls back to whatever the cache holds.
  Future<void> _loadInitial() async {
    final client = _client;
    if (client == null) return;
    final me = ref.read(accordAuthProvider).runtimeType == AccordAuthLoggedIn
        ? (ref.read(accordAuthProvider) as AccordAuthLoggedIn).session
        : null;
    if (me != null) {
      _displayName.text = me.username;
    }
    final result = await client.users.getMe();
    if (!mounted) return;
    final data = result.data;
    if (result.ok && data is AccordUser) {
      _displayName.text = data.displayName ?? data.username;
      _bio.text = data.bio ?? '';
      final accent = data.accentColor;
      if (accent is int && accent > 0) _accentColor = 0xFF000000 | (accent & 0xFFFFFF);
      ref.read(accordUsersControllerProvider.notifier).upsert(data);
    }
    setState(() => _loaded = true);
  }

  Future<void> _pickAvatar() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    if (file?.bytes == null) return;
    setState(() {
      _newAvatarBytes = file!.bytes!;
      _newAvatarFilename = file.name;
      // An uploaded image hides the colored fallback, so reset the picker to
      // transparent — the chosen color only applies to imageless avatars.
      _accentColor = null;
    });
  }

  Future<void> _save() async {
    final client = _client;
    if (client == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = <String, dynamic>{
      'display_name': _displayName.text.trim(),
      'bio': _bio.text.trim(),
      // null clears the accent server-side, falling back to the auto color.
      'accent_color': _accentColor == null ? null : (_accentColor! & 0xFFFFFF),
    };
    if (_newAvatarBytes != null) {
      body['avatar'] = AccordCDN.buildDataUri(
          _toUint8(_newAvatarBytes!), _newAvatarFilename ?? 'avatar.png');
    }
    final result = await client.users.updateMe(body);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      setState(() =>
          _error = result.error?.toString() ?? 'Failed to save profile');
      return;
    }
    final updated = result.data;
    if (updated is AccordUser) {
      ref.read(accordUsersControllerProvider.notifier).upsert(updated);
      // The member caches hold their own AccordUser per member; propagate the
      // change so message authors and the roster update, not just surfaces that
      // read the global user cache.
      for (final spaceId in activeMemberSpaces) {
        ref
            .read(accordMembersControllerProvider(spaceId).notifier)
            .applyUserUpdate(updated);
      }
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final session = ref.watch(accordAuthProvider
        .select((s) => s is AccordAuthLoggedIn ? s.session : null));
    final me = session == null
        ? null
        : ref.watch(accordUsersControllerProvider
            .select((m) => m[session.userId]));
    final avatarUrl = me == null
        ? null
        : accordAvatarUrl(me, session?.server.cdnUrl);
    final previewBg = _accentColor != null
        ? Color(_accentColor!)
        : accordIdColor(session?.userId ?? '');

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.person_outline,
                      size: 18, color: colors.dirtyWhite),
                  const SizedBox(width: 8),
                  Text('Edit profile', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (!_loaded)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: previewBg,
                        backgroundImage: _newAvatarBytes != null
                            ? MemoryImage(_toUint8(_newAvatarBytes!))
                            : (avatarUrl != null
                                ? CachedNetworkImageProvider(avatarUrl)
                                : null),
                        child: (_newAvatarBytes == null && avatarUrl == null)
                            ? Text(
                                (session?.username.isNotEmpty == true
                                        ? session!.username[0]
                                        : '?')
                                    .toUpperCase(),
                                style: TextStyle(
                                    fontSize: 24,
                                    color: accordOnColor(previewBg)),
                              )
                            : null,
                      ),
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: IconButton(
                          tooltip: 'Change avatar',
                          onPressed: _busy ? null : _pickAvatar,
                          icon: const Icon(Icons.camera_alt, size: 18),
                          style: IconButton.styleFrom(
                            backgroundColor: colors.darkGray,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _displayName,
                  enabled: !_busy,
                  decoration: const InputDecoration(labelText: 'Display name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bio,
                  enabled: !_busy,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Bio',
                    hintText: 'A short bio shown on your profile',
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Avatar background',
                      style: theme.textTheme.bodySmall!
                          .copyWith(color: colors.dirtyWhite)),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ColorSwatch(
                      color: accordIdColor(session?.userId ?? ''),
                      selected: _accentColor == null,
                      transparent: true,
                      label: 'Transparent (auto)',
                      onTap: _busy
                          ? null
                          : () => setState(() => _accentColor = null),
                    ),
                    for (final argb in _avatarSwatches)
                      _ColorSwatch(
                        color: Color(argb),
                        selected: _accentColor == argb,
                        label: null,
                        onTap: _busy
                            ? null
                            : () => setState(() => _accentColor = argb),
                      ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!,
                      style: theme.textTheme.bodySmall!
                          .copyWith(color: colors.red)),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed:
                          _busy ? null : () => Navigator.of(context).maybePop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// MemoryImage needs a Uint8List; FilePicker returns one from `bytes`, but it's
// typed as List<int> through accordkit helpers — cast/copy on the boundary.
Uint8List _toUint8(List<int> bytes) =>
    bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

/// A selectable avatar-background swatch. The [transparent] variant marks the
/// "no chosen color" option (the avatar falls back to its auto color), drawn
/// with a slash over the preview tint.
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
    this.label,
    this.transparent = false,
  });

  final Color color;
  final bool selected;
  final VoidCallback? onTap;
  final String? label;
  final bool transparent;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Tooltip(
      message: label ?? '',
      child: GestureDetector(
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
          child: Icon(
            transparent
                ? Icons.format_color_reset_outlined
                : (selected ? Icons.check : null),
            size: 18,
            color: accordOnColor(color),
          ),
        ),
      ),
    );
  }
}
