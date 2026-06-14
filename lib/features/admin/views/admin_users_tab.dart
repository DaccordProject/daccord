import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Instance-admin "Users" tab: paginated user list with search, admin-flag
/// toggle, disable/enable, password reset and delete. Mirrors the reference
/// `server_management_panel` Users page. Uses `client.adminApi.*`.
class AdminUsersTab extends ConsumerStatefulWidget {
  const AdminUsersTab({super.key});

  @override
  ConsumerState<AdminUsersTab> createState() => _AdminUsersTabState();
}

const _userPageSize = 50;

class _AdminUsersTabState extends ConsumerState<AdminUsersTab> {
  final List<AccordUser> _users = [];
  final _search = TextEditingController();
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _busy = false;
  String? _error;

  AccordClient? get _client => ref.accordClient;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Map<String, dynamic> _query({String? after}) {
    final q = <String, dynamic>{'limit': _userPageSize};
    final search = _search.text.trim();
    if (search.isNotEmpty) q['query'] = search;
    if (after != null) q['after'] = after;
    return q;
  }

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await client.adminApi.listUsers(query: _query());
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _loading = false;
        _error = result.error?.toString() ?? 'Failed to load users';
      });
      return;
    }
    final data = result.data;
    final fresh = data is List ? data.cast<AccordUser>() : <AccordUser>[];
    setState(() {
      _loading = false;
      _users
        ..clear()
        ..addAll(fresh);
      _hasMore = fresh.length >= _userPageSize;
    });
  }

  Future<void> _loadMore() async {
    final client = _client;
    if (client == null || _loadingMore || !_hasMore || _users.isEmpty) return;
    setState(() => _loadingMore = true);
    final result =
        await client.adminApi.listUsers(query: _query(after: _users.last.id));
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _loadingMore = false;
        _error = result.error?.toString() ?? 'Failed to load more';
      });
      return;
    }
    final data = result.data;
    final fresh = data is List ? data.cast<AccordUser>() : <AccordUser>[];
    final existing = _users.map((u) => u.id).toSet();
    final deduped = fresh.where((u) => !existing.contains(u.id)).toList();
    setState(() {
      _loadingMore = false;
      _users.addAll(deduped);
      _hasMore = fresh.length >= _userPageSize && deduped.isNotEmpty;
    });
  }

  Future<bool?> _confirm(String title, String message, String action,
      {bool danger = false}) {
    final colors = BonfireThemeExtension.of(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: danger
                ? FilledButton.styleFrom(backgroundColor: colors.red)
                : null,
            child: Text(action),
          ),
        ],
      ),
    );
  }

  Future<void> _setAdmin(AccordUser user, bool value) async {
    final client = _client;
    if (client == null) return;
    final result =
        await client.adminApi.updateUser(user.id, {'is_admin': value});
    if (!mounted) return;
    if (!result.ok) {
      setState(() =>
          _error = result.error?.toString() ?? 'Failed to update user');
      return;
    }
    setState(() => user.isAdmin = value);
  }

  Future<void> _setDisabled(AccordUser user, bool disable) async {
    final ok = await _confirm(
      disable ? 'Disable user' : 'Enable user',
      disable
          ? "Disable '${user.username}'? They will be unable to log in."
          : "Re-enable '${user.username}'? They will be able to log in again.",
      disable ? 'Disable' : 'Enable',
      danger: disable,
    );
    if (ok != true) return;
    final client = _client;
    if (client == null) return;
    setState(() => _busy = true);
    final result =
        await client.adminApi.updateUser(user.id, {'disabled': disable});
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      setState(() =>
          _error = result.error?.toString() ?? 'Failed to update user');
      return;
    }
    setState(() => user.disabled = disable);
  }

  Future<void> _resetPassword(AccordUser user) async {
    final newPassword = await showDialog<String>(
      context: context,
      builder: (ctx) => _ResetPasswordDialog(username: user.username),
    );
    if (newPassword == null) return;
    final client = _client;
    if (client == null) return;
    setState(() => _busy = true);
    final result = await client.adminApi
        .resetUserPassword(user.id, {'new_password': newPassword});
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      setState(() =>
          _error = result.error?.toString() ?? 'Failed to reset password');
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text("Password reset for ${user.username}")),
    );
  }

  Future<void> _delete(AccordUser user) async {
    final ok = await _confirm(
      'Delete user',
      "Delete '${user.username}'? This cannot be undone.",
      'Delete',
      danger: true,
    );
    if (ok != true) return;
    final client = _client;
    if (client == null) return;
    setState(() => _busy = true);
    final result = await client.adminApi.deleteUser(user.id);
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _busy = false;
        _error = result.error?.toString() ?? 'Failed to delete user';
      });
      return;
    }
    setState(() {
      _busy = false;
      _users.removeWhere((u) => u.id == user.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 18),
                    hintText: 'Search by username',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _load(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _loading ? null : _load,
                child: const Text('Search'),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(_error!,
                style:
                    theme.textTheme.bodySmall!.copyWith(color: colors.red)),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _users.isEmpty
                  ? Center(
                      child: Text('No users found.',
                          style: theme.textTheme.bodyMedium))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: _users.length + (_hasMore ? 1 : 0),
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        if (i >= _users.length) {
                          return Center(
                            child: _loadingMore
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  )
                                : TextButton(
                                    onPressed: _loadMore,
                                    child: const Text('Load more'),
                                  ),
                          );
                        }
                        return _UserRow(
                          user: _users[i],
                          busy: _busy,
                          onSetAdmin: (v) => _setAdmin(_users[i], v),
                          onToggleDisabled: () =>
                              _setDisabled(_users[i], !_users[i].disabled),
                          onResetPassword: () => _resetPassword(_users[i]),
                          onDelete: () => _delete(_users[i]),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.busy,
    required this.onSetAdmin,
    required this.onToggleDisabled,
    required this.onResetPassword,
    required this.onDelete,
  });

  final AccordUser user;
  final bool busy;
  final ValueChanged<bool> onSetAdmin;
  final VoidCallback onToggleDisabled;
  final VoidCallback onResetPassword;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final initial =
        user.username.isNotEmpty ? user.username[0].toUpperCase() : '?';
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: colors.primary,
        child: Text(initial, style: const TextStyle(color: Colors.white)),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              user.username,
              style: theme.textTheme.titleSmall!.copyWith(
                color: user.disabled ? colors.gray : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (user.disabled) ...[
            const SizedBox(width: 6),
            _Badge('Disabled', colors.gray),
          ] else if (user.isAdmin) ...[
            const SizedBox(width: 6),
            _Badge('Admin', colors.primary),
          ],
        ],
      ),
      subtitle: Text(user.id, style: theme.textTheme.bodySmall),
      trailing: PopupMenuButton<String>(
        enabled: !busy,
        icon: const Icon(Icons.more_vert, size: 18),
        onSelected: (value) {
          switch (value) {
            case 'admin':
              onSetAdmin(!user.isAdmin);
            case 'disable':
              onToggleDisabled();
            case 'reset':
              onResetPassword();
            case 'delete':
              onDelete();
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'admin',
            child: Text(user.isAdmin ? 'Remove admin' : 'Make admin'),
          ),
          PopupMenuItem(
            value: 'disable',
            child: Text(user.disabled ? 'Enable account' : 'Disable account'),
          ),
          if (!user.bot)
            const PopupMenuItem(
              value: 'reset',
              child: Text('Reset password'),
            ),
          PopupMenuItem(
            value: 'delete',
            child: Text('Delete user', style: TextStyle(color: colors.red)),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 10, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Prompts for (and confirms) a new password during an admin reset.
class _ResetPasswordDialog extends StatefulWidget {
  const _ResetPasswordDialog({required this.username});

  final String username;

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    final pw = _password.text;
    if (pw.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }
    if (pw != _confirm.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    Navigator.of(context).pop(pw);
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return AlertDialog(
      title: Text('Reset password — ${widget.username}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _password,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'New password',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Confirm password',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: colors.red, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Reset')),
      ],
    );
  }
}
