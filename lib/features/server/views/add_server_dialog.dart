import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/server/utils/server_uri.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/views/accord_discovery.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the in-app "Add a Server" dialog. Mirrors the reference client's
/// add-server flow: an **Enter URL** tab (paste a server URL or `daccord://`
/// link and authenticate without leaving the app) and a **Browse** tab (the
/// public-space directory). [initialUrl] pre-fills the URL field — used when a
/// `daccord://` deep link is opened while already signed in. [joinSpaceId], when
/// set, is joined on the new connection once authentication succeeds — used when
/// the discovery browser sends the user here to sign in before joining a public
/// space.
///
/// Authentication here goes through the multi-connection add-server methods on
/// [AccordAuth], which keep the current connection active until the new one
/// succeeds (so the home screen is never bounced to login mid-flow).
Future<void> showAddServerDialog(
  BuildContext context, {
  String? initialUrl,
  String? joinSpaceId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        _AddServerDialog(initialUrl: initialUrl, joinSpaceId: joinSpaceId),
  );
}

enum _UrlStep { url, credentials, mfa }

class _AddServerDialog extends ConsumerStatefulWidget {
  const _AddServerDialog({this.initialUrl, this.joinSpaceId});

  final String? initialUrl;
  final String? joinSpaceId;

  @override
  ConsumerState<_AddServerDialog> createState() => _AddServerDialogState();
}

class _AddServerDialogState extends ConsumerState<_AddServerDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _mfaCtrl = TextEditingController();

  _UrlStep _step = _UrlStep.url;
  AccordServer? _server;
  String? _mfaTicket;
  String? _error;
  bool _busy = false;

  /// Space to join on the new connection once auth succeeds (from a discovery
  /// listing). Set at construction or by the embedded Browse tab.
  String? _pendingJoinSpaceId;

  /// Invite code to redeem once connected (from an `invite/` deep link or a
  /// `?invite=` URL). Redeemed via `invites.accept` in [_finishAfterConnect].
  String? _pendingInviteCode;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialUrl;
    if (initial != null && initial.isNotEmpty) {
      _urlCtrl.text = initial;
      _pendingInviteCode = ServerUri.parseServerUrl(initial)?.invite;
    }
    _pendingJoinSpaceId = widget.joinSpaceId;
  }

  @override
  void dispose() {
    _tabs.dispose();
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _mfaCtrl.dispose();
    super.dispose();
  }

  AccordAuth get _auth => ref.read(accordAuthProvider.notifier);

  void _fail(String message) => setState(() {
    _busy = false;
    _error = message;
  });

  /// Connection succeeded (and is now the active one). Joins a pending discovery
  /// space if any, then closes the dialog.
  Future<void> _finishAfterConnect() async {
    final client = _auth.client;
    final spaceId = _pendingJoinSpaceId;
    if (client != null && spaceId != null && spaceId.isNotEmpty) {
      final result = await client.spaces.join(spaceId);
      final space = result.data;
      if (space is AccordSpace) {
        ref.read(spacesControllerProvider.notifier).upsertSpace(space);
      }
    }
    // Redeem an invite code (deep link / ?invite=) against the now-active
    // connection. The accept response carries the joined space.
    final invite = _pendingInviteCode;
    if (client != null && invite != null && invite.isNotEmpty) {
      final result = await client.invites.accept(invite);
      final space = result.data;
      if (space is AccordSpace) {
        ref.read(spacesControllerProvider.notifier).upsertSpace(space);
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _continueFromUrl() async {
    final parsed = ServerUri.parseServerUrl(_urlCtrl.text);
    final server = parsed?.server;
    if (parsed == null || server == null) {
      _fail('Enter a valid server URL');
      return;
    }
    // A pasted invite URL carries its code here too.
    if (parsed.invite != null && parsed.invite!.isNotEmpty) {
      _pendingInviteCode = parsed.invite;
    }

    // Already connected to this server: switch to it (and join a pending space).
    final existing = _auth.keyForBaseUrl(server.baseUrl);
    if (existing != null) {
      _auth.setActiveServer(existing);
      await _finishAfterConnect();
      return;
    }

    setState(() {
      _server = server;
      _error = null;
      _busy = true;
    });

    // A link that carries a token can authenticate directly.
    final token = parsed.token;
    if (token != null && token.isNotEmpty) {
      final error = await _auth.addServerWithToken(
        server: server,
        token: token,
      );
      if (!mounted) return;
      if (error == null) {
        await _finishAfterConnect();
      } else {
        _fail(error);
      }
      return;
    }

    // Otherwise collect credentials for this server.
    setState(() {
      _busy = false;
      _step = _UrlStep.credentials;
    });
  }

  Future<void> _submitCredentials() async {
    final server = _server;
    if (server == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await _auth.addServerWithCredentials(
      server: server,
      username: _userCtrl.text.trim(),
      password: _passCtrl.text,
    );
    if (!mounted) return;
    if (outcome.ok) {
      await _finishAfterConnect();
    } else if (outcome.needsMfa) {
      setState(() {
        _busy = false;
        _mfaTicket = outcome.mfaTicket;
        _step = _UrlStep.mfa;
      });
    } else {
      _fail(outcome.error ?? 'Login failed');
    }
  }

  Future<void> _submitMfa() async {
    final server = _server;
    final ticket = _mfaTicket;
    if (server == null || ticket == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await _auth.addServerSubmitMfa(
      server,
      ticket,
      _mfaCtrl.text.trim(),
    );
    if (!mounted) return;
    if (outcome.ok) {
      await _finishAfterConnect();
    } else {
      _fail(outcome.error ?? 'Invalid two-factor code');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Dialog(
      backgroundColor: colors.foreground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  Icon(Icons.dns_outlined, size: 20, color: colors.dirtyWhite),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Add a Server',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, size: 20, color: colors.gray),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: 'Enter URL'),
                Tab(text: 'Browse'),
              ],
            ),
            Flexible(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _urlTab(theme, colors),
                  AccordDiscoveryBody(
                    onJoinRequiresAuth: (serverUrl, spaceId) {
                      // Stay in this dialog: pre-fill the URL tab for the
                      // listing's instance and join that space once signed in.
                      setState(() {
                        _urlCtrl.text = serverUrl;
                        _pendingJoinSpaceId = spaceId;
                        _step = _UrlStep.url;
                        _server = null;
                        _mfaTicket = null;
                        _error = null;
                        _busy = false;
                      });
                      _tabs.animateTo(0);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _urlTab(ThemeData theme, BonfireThemeExtension colors) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_step == _UrlStep.url) ...[
            Text('Server URL', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            TextField(
              controller: _urlCtrl,
              autofocus: true,
              enabled: !_busy,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'chat.example.com  or  daccord://connect/...',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _busy ? null : _continueFromUrl(),
            ),
          ] else ...[
            Text(
              'Sign in to ${_server?.name ?? _server?.baseUrl ?? 'server'}',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 12),
            if (_step == _UrlStep.credentials) ...[
              TextField(
                controller: _userCtrl,
                enabled: !_busy,
                autofocus: true,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _passCtrl,
                enabled: !_busy,
                obscureText: true,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _busy ? null : _submitCredentials(),
              ),
            ] else ...[
              TextField(
                controller: _mfaCtrl,
                enabled: !_busy,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Two-factor code',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _busy ? null : _submitMfa(),
              ),
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_step != _UrlStep.url && !_busy)
                TextButton(
                  onPressed: () => setState(() {
                    _step = _UrlStep.url;
                    _error = null;
                  }),
                  child: const Text('Back'),
                ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy ? null : _primaryAction,
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_primaryLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String get _primaryLabel {
    switch (_step) {
      case _UrlStep.url:
        return 'Connect';
      case _UrlStep.credentials:
        return 'Sign in';
      case _UrlStep.mfa:
        return 'Verify';
    }
  }

  void _primaryAction() {
    switch (_step) {
      case _UrlStep.url:
        _continueFromUrl();
        break;
      case _UrlStep.credentials:
        _submitCredentials();
        break;
      case _UrlStep.mfa:
        _submitMfa();
        break;
    }
  }
}
