import 'package:bonfire/features/automod/views/automod_panel.dart';
import 'package:bonfire/features/admin/views/admin_reports_tab.dart';
import 'package:bonfire/features/admin/views/admin_settings_tab.dart';
import 'package:bonfire/features/admin/views/admin_spaces_tab.dart';
import 'package:bonfire/features/admin/views/admin_users_tab.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Instance-level (server-wide) administration panel — visible only to instance
/// admins (`session.isAdmin`). Five tabs extending the reference client's
/// `server_management_panel`: Spaces, Users, Reports, Settings, AutoMod.
/// Non-admins are shown an access-denied placeholder rather than the tabs.
class AccordAdminPanel extends ConsumerWidget {
  const AccordAdminPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final isAdmin = ref.watchIsAdmin();
    return DefaultTabController(
      length: 5,
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
          bottom: isAdmin
              ? const TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(text: 'Spaces'),
                    Tab(text: 'Users'),
                    Tab(text: 'Reports'),
                    Tab(text: 'Settings'),
                    Tab(text: 'AutoMod'),
                  ],
                )
              : null,
        ),
        body: isAdmin
            ? const TabBarView(
                children: [
                  AdminSpacesTab(),
                  AdminUsersTab(),
                  AdminReportsTab(),
                  AdminSettingsTab(),
                  AutomodPanel(),
                ],
              )
            : Center(
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
      ),
    );
  }
}
