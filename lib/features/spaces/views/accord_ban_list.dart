import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the ban list dialog for [spaceId]. Gated on `ban_members` by the
/// caller (space settings). Lists banned users with their reason and an unban
/// action per row. Mirrors the reference client's ban management dialog.
Future<void> showAccordBanList(
  BuildContext context, {
  required String spaceId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _BanList(spaceId: spaceId),
  );
}

class _BanList extends ConsumerStatefulWidget {
  const _BanList({required this.spaceId});

  final String spaceId;

  @override
  ConsumerState<_BanList> createState() => _BanListState();
}

class _BanListState extends ConsumerState<_BanList> {
  List<_Ban>? _bans;
  String? _error;
  bool _busy = false;

  AccordClient? get _client => ref.read(
        accordAuthProvider
            .select((s) => s is AccordAuthLoggedIn ? s.client : null),
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await client.bans.list(widget.spaceId);
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _busy = false;
        _error = result.error?.toString() ?? 'Failed to load bans';
      });
      return;
    }
    final raw = result.data;
    final parsed = <_Ban>[];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is Map) parsed.add(_Ban.fromJson(entry));
      }
    }
    setState(() {
      _busy = false;
      _bans = parsed;
    });
  }

  Future<void> _unban(_Ban ban) async {
    final client = _client;
    if (client == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unban member?'),
        content: Text('Allow ${ban.name} back into the space?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Unban'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final result = await client.bans.remove(widget.spaceId, ban.userId);
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _busy = false;
        _error = result.error?.toString() ?? 'Failed to unban';
      });
      return;
    }
    setState(() {
      _bans?.removeWhere((b) => b.userId == ban.userId);
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final bans = _bans;
    // Ensure any bans the API returned with only a userId resolve their name
    // on the next rebuild via the on-demand user cache.
    final users = ref.watch(accordUsersControllerProvider);
    final ensureUser =
        ref.read(accordUsersControllerProvider.notifier).ensure;
    if (bans != null) {
      for (final b in bans) {
        if (b.username == null) {
          final cached = users[b.userId];
          if (cached != null) {
            b.username = cached.username;
            b.displayName = cached.displayName ?? b.displayName;
          } else {
            ensureUser(b.userId);
          }
        }
      }
    }

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.gavel, size: 18, color: colors.dirtyWhite),
                  const SizedBox(width: 8),
                  Text('Banned members', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _busy ? null : _load,
                    icon: const Icon(Icons.refresh, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!,
                      style: theme.textTheme.bodySmall!
                          .copyWith(color: colors.red)),
                ),
              Flexible(
                child: _busy && bans == null
                    ? const Center(child: CircularProgressIndicator())
                    : bans == null || bans.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: Text(
                                bans == null
                                    ? 'Loading…'
                                    : 'No bans in this space.',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: bans.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final ban = bans[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  radius: 16,
                                  child: Text(ban.initial),
                                ),
                                title: Text(ban.name,
                                    style: theme.textTheme.titleSmall),
                                subtitle: Text(
                                  ban.reason.isEmpty
                                      ? 'No reason given'
                                      : ban.reason,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: TextButton.icon(
                                  onPressed: _busy ? null : () => _unban(ban),
                                  icon: const Icon(Icons.lock_open, size: 16),
                                  label: const Text('Unban'),
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
}

/// Loosely-typed shape of a ban entry. The bans API returns raw JSON; fields
/// vary by server, so we accept the common subset and let the dialog hydrate
/// the name via the on-demand user cache when only the userId came back.
class _Ban {
  _Ban({
    required this.userId,
    required this.reason,
    this.username,
    this.displayName,
  });

  final String userId;
  final String reason;
  String? username;
  String? displayName;

  /// displayName → username → "Unknown". Never the raw snowflake (#25).
  String get name {
    final d = displayName;
    if (d != null && d.isNotEmpty) return d;
    final u = username;
    if (u != null && u.isNotEmpty) return u;
    return 'Unknown';
  }

  String get initial {
    final src = name.trim();
    return src.isEmpty ? '?' : src.substring(0, 1).toUpperCase();
  }

  factory _Ban.fromJson(Map data) {
    final user = data['user'];
    String? userId;
    String? username;
    String? displayName;
    if (user is Map) {
      userId = user['id']?.toString();
      username = user['username']?.toString();
      displayName = user['display_name']?.toString();
    }
    userId ??= data['user_id']?.toString() ?? '';
    return _Ban(
      userId: userId,
      reason: data['reason']?.toString() ?? '',
      username: username,
      displayName: displayName,
    );
  }
}
