import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Lists the locally saved Accord accounts and lets the user switch between
/// them, add another, or remove one. The Accord analogue of Bonfire's
/// Discord-token account switcher.
class AccountSwitcherScreen extends ConsumerStatefulWidget {
  const AccountSwitcherScreen({super.key});

  @override
  ConsumerState<AccountSwitcherScreen> createState() =>
      _AccountSwitcherScreenState();
}

class _AccountSwitcherScreenState extends ConsumerState<AccountSwitcherScreen> {
  List<AccordSession>? _accounts;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final accounts = await ref.read(accordAuthProvider.notifier).listAccounts();
    if (mounted) setState(() => _accounts = accounts);
  }

  String? get _activeKey {
    final state = ref.read(accordAuthProvider);
    if (state is AccordAuthLoggedIn) {
      return '${state.session.userId}@${state.session.server.baseUrl}';
    }
    return null;
  }

  void _switchTo(AccordSession session) {
    ref.read(accordAuthProvider.notifier).switchTo(session);
    context.go('/spaces');
  }

  Future<void> _remove(AccordSession session) async {
    await ref.read(accordAuthProvider.notifier).removeAccount(session);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final accounts = _accounts;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Accounts',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 24),
              if (accounts == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: LoadingView(),
                )
              else if (accounts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No saved accounts yet.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              else
                for (final account in accounts)
                  _AccountTile(
                    session: account,
                    active: '${account.userId}@${account.server.baseUrl}' ==
                        _activeKey,
                    onTap: () => _switchTo(account),
                    onRemove: () => _remove(account),
                  ),
              const SizedBox(height: 16),
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () => context.go('/login'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: Text(
                    'Add account',
                    style: theme.textTheme.titleSmall!
                        .copyWith(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.go('/spaces'),
                child: Text('Back', style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.session,
    required this.active,
    required this.onTap,
    required this.onRemove,
  });

  final AccordSession session;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  String get _initial => accordInitial(session.username);

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.darkGray,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: active
              ? BorderSide(color: colors.primary, width: 2)
              : BorderSide.none,
        ),
        child: ListTile(
          onTap: onTap,
          leading: CircleAvatar(
            backgroundColor: colors.primary,
            child: Text(_initial,
                style: theme.textTheme.titleSmall!
                    .copyWith(color: Colors.white)),
          ),
          title: Text(session.username, style: theme.textTheme.bodyLarge),
          subtitle: Text(
            session.server.name ?? session.server.baseUrl,
            style: theme.textTheme.bodySmall,
          ),
          trailing: IconButton(
            tooltip: 'Remove',
            icon: Icon(Icons.close, color: colors.dirtyWhite, size: 20),
            onPressed: onRemove,
          ),
        ),
      ),
    );
  }
}
