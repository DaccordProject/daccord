# Administrative User Management

Priority: 19
Depends on: Role-Based Permissions, User Management
Status: Complete

Permission-gated admin actions on space members: kick, ban/unban (with reasons, purge, bulk), role assignment/management, moderate (timeout/mute/deafen), nickname editing, user/message reporting, report management, and audit logging. Three entry points — member list context menu, space icon admin submenu, channel banner dropdown — all routed through `ClientAdmin` delegation layer. All dialogs extend `ModalBase`.

## Key Files

| File | Role |
|------|------|
| `scripts/client/client_admin.gd` | Admin API delegation layer: kick, ban, unban, roles, moderate, reports, audit log |
| `scripts/autoload/client.gd` | `has_permission()`, `get_my_highest_role_position()`, member/role caches |
| `scripts/client/client_gateway_members.gd` | Gateway handlers for member join/leave/update |
| `scripts/client/client_gateway_events.gd` | Gateway handlers for ban create/delete, report create |
| `scripts/autoload/app_state.gd` | Signals: `members_updated`, `bans_updated`, `roles_updated`, `reports_updated` |
| `scenes/common/modal_base.gd` | Base class for all modal dialogs |
| `scripts/helpers/dialog_helper.gd` | Static helpers: `open()`, `confirm()` |
| `scenes/members/member_item.gd` | Member context menu with permission-gated admin actions, role toggles |
| `scenes/admin/ban_dialog.gd` | Two-step ban dialog with reason, purge duration |
| `scenes/admin/ban_list_dialog.gd` | Ban list with search, single/bulk unban, pagination |
| `scenes/admin/ban_row.gd` | Individual ban row with checkbox, unban button |
| `scenes/admin/role_management_dialog.gd` | Two-panel role editor with hierarchy enforcement |
| `scenes/admin/role_row.gd` | Role row with reorder arrows, color, member count |
| `scenes/admin/moderate_member_dialog.gd` | Timeout/mute/deafen dialog |
| `scenes/admin/nickname_dialog.gd` | Nickname editing dialog |
| `scenes/admin/report_dialog.gd` | User/message reporting with 7 categories |
| `scenes/admin/report_list_dialog.gd` | Report management with status filter, actions, server-wide mode |
| `scenes/admin/report_row.gd` | Report row with action menu (reviewed/delete/kick/ban) |
| `scenes/admin/audit_log_dialog.gd` | Audit log viewer with 15 action filters, search, pagination |
| `scenes/admin/audit_log_row.gd` | Audit log row with action icons, user resolution, relative time |
| `scenes/admin/confirm_dialog.gd` | Reusable confirm dialog with danger mode |
| `scenes/sidebar/guild_bar/guild_icon.gd` | Space icon Administration submenu |
| `scenes/sidebar/channels/banner.gd` | Channel banner Administration dropdown |
| `addons/accordkit/rest/endpoints/members_api.gd` | Member REST: kick, add_role, remove_role, update |
| `addons/accordkit/rest/endpoints/bans_api.gd` | Ban REST: list, create, remove |
| `addons/accordkit/rest/endpoints/roles_api.gd` | Role REST: create, update, delete, reorder |
| `addons/accordkit/rest/endpoints/audit_logs_api.gd` | Audit log REST: list |
| `addons/accordkit/models/permission.gd` | Permission constants and `has()` check with admin wildcard |
