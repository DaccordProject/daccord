import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/admin/views/admin_list_scaffold.dart';
import 'package:bonfire/shared/components/load_more_footer.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/self_loading_list.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/shared/components/label_pill.dart';
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

class _AdminUsersTabState extends ConsumerState<AdminUsersTab>
    with PaginatedListState<AccordUser, AdminUsersTab> {
  final _search = TextEditingController();
  bool _busy = false;

  AccordClient? get _client => ref.accordClient;

  @override
  int get pageSize => _userPageSize;

  @override
  bool get canLoad => _client != null;

  @override
  String itemId(AccordUser item) => item.id;

  @override
  Future<RestResult> fetchPage({String? before}) =>
      _client!.adminApi.listUsers(query: _query(after: before));

  @override
  List<AccordUser> parseItems(Object? data) =>
      data is List ? data.cast<AccordUser>() : <AccordUser>[];

  @override
  String loadError(RestResult result) => result.errorOr('Failed to load users');

  @override
  String loadMoreError(RestResult result) =>
      result.errorOr('Failed to load more');

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

  Future<bool?> _confirm(
    String title,
    String message,
    String action, {
    bool danger = false,
  }) {
    return showConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: action,
      danger: danger,
    );
  }

  Future<void> _setAdmin(AccordUser user, bool value) async {
    final client = _client;
    if (client == null) return;
    final result = await client.adminApi.updateUser(user.id, {
      'is_admin': value,
    });
    if (!mounted) return;
    if (!result.ok) {
      setState(() => error = result.errorOr('Failed to update user'));
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
    final result = await client.adminApi.updateUser(user.id, {
      'disabled': disable,
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      setState(() => error = result.errorOr('Failed to update user'));
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
    final result = await client.adminApi.resetUserPassword(user.id, {
      'new_password': newPassword,
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      setState(() => error = result.errorOr('Failed to reset password'));
      return;
    }
    showInfoSnack(context, "Password reset for ${user.username}");
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
        error = result.errorOr('Failed to delete user');
      });
      return;
    }
    setState(() {
      _busy = false;
      items.removeWhere((u) => u.id == user.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdminListScaffold(
      error: error,
      loading: loading,
      isEmpty: items.isEmpty,
      emptyMessage: 'No users found.',
      header: Padding(
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
                onSubmitted: (_) => load(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: loading ? null : load,
              child: const Text('Search'),
            ),
          ],
        ),
      ),
      list: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: items.length + (hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          if (i >= items.length) {
            return LoadMoreFooter(loading: loadingMore, onPressed: loadMore);
          }
          return _UserRow(
            user: items[i],
            busy: _busy,
            onSetAdmin: (v) => _setAdmin(items[i], v),
            onToggleDisabled: () => _setDisabled(items[i], !items[i].disabled),
            onResetPassword: () => _resetPassword(items[i]),
            onDelete: () => _delete(items[i]),
          );
        },
      ),
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
    final initial = accordInitial(user.username);
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
            LabelPill('Disabled', color: colors.gray),
          ] else if (user.isAdmin) ...[
            const SizedBox(width: 6),
            LabelPill('Admin', color: colors.primary),
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
            const PopupMenuItem(value: 'reset', child: Text('Reset password')),
          PopupMenuItem(
            value: 'delete',
            child: Text('Delete user', style: TextStyle(color: colors.red)),
          ),
        ],
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
