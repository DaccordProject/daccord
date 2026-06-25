import 'package:bonfire/features/admin/views/admin_reports_tab.dart';
import 'package:bonfire/features/admin/views/admin_settings_tab.dart';
import 'package:bonfire/features/admin/views/admin_spaces_tab.dart';
import 'package:bonfire/features/admin/views/admin_users_tab.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Instance-level (server-wide) administration panel — visible only to instance
/// admins (`session.isAdmin`). Four tabs mirroring the reference client's
/// `server_management_panel`: Spaces, Users, Reports, Settings. Non-admins are
/// shown an access-denied placeholder rather than the tabs.
class AccordAdminPanel extends ConsumerWidget {
  const AccordAdminPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final session = ref.watch(
      accordAuthProvider
          .select((s) => s is AccordAuthLoggedIn ? s.session : null),
    );
    final isAdmin = session?.isAdmin ?? false;

    if (!isAdmin) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.foreground,
          title: const Text('Server administration'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/spaces'),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 48, color: colors.gray),
                const SizedBox(height: 12),
                Text(
                  'You do not have access to this area.',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.foreground,
          title: const Text('Server administration'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/spaces'),
          ),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Spaces'),
              Tab(text: 'Users'),
              Tab(text: 'Reports'),
              Tab(text: 'Settings'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            AdminSpacesTab(),
            AdminUsersTab(),
            AdminReportsTab(),
            AdminSettingsTab(),
          ],
        ),
      ),
    );
  }
}
