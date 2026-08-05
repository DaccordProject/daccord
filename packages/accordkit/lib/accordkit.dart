/// AccordKit — an Accord protocol client for Dart.
///
/// Provides a REST client, a gateway WebSocket client with reconnect and
/// heartbeating, and data models for working with Daccord servers.
library;

// Core
export 'src/core/accord_client.dart';
export 'src/core/accord_config.dart';

// REST
export 'src/rest/accord_error.dart';
export 'src/rest/accord_rest.dart';
export 'src/rest/endpoint_base.dart';
export 'src/rest/multipart_form.dart';
export 'src/rest/paginator.dart';
export 'src/rest/rest_result.dart';

// REST endpoints
export 'src/rest/endpoints/admin_api.dart';
export 'src/rest/endpoints/applications_api.dart';
export 'src/rest/endpoints/audit_logs_api.dart';
export 'src/rest/endpoints/auth_api.dart';
export 'src/rest/endpoints/bans_api.dart';
export 'src/rest/endpoints/channels_api.dart';
export 'src/rest/endpoints/directory_api.dart';
export 'src/rest/endpoints/emojis_api.dart';
export 'src/rest/endpoints/federation_api.dart';
export 'src/rest/endpoints/interactions_api.dart';
export 'src/rest/endpoints/invites_api.dart';
export 'src/rest/endpoints/members_api.dart';
export 'src/rest/endpoints/messages_api.dart';
export 'src/rest/endpoints/plugins_api.dart';
export 'src/rest/endpoints/reactions_api.dart';
export 'src/rest/endpoints/reports_api.dart';
export 'src/rest/endpoints/roles_api.dart';
export 'src/rest/endpoints/soundboard_api.dart';
export 'src/rest/endpoints/spaces_api.dart';
export 'src/rest/endpoints/users_api.dart';
export 'src/rest/endpoints/voice_api.dart';

// Gateway
export 'src/gateway/gateway_connection.dart';
export 'src/gateway/gateway_events.dart';
export 'src/gateway/gateway_intents.dart';
export 'src/gateway/gateway_opcodes.dart';
export 'src/gateway/gateway_socket.dart';

// Voice
export 'src/voice/voice_manager.dart';

// Models
export 'src/models/accord_relationship.dart';
export 'src/models/activity.dart';
export 'src/models/application.dart';
export 'src/models/attachment.dart';
export 'src/models/audit_log_entry.dart';
export 'src/models/call_signal.dart';
export 'src/models/channel.dart';
export 'src/models/command.dart';
export 'src/models/embed.dart';
export 'src/models/emoji.dart';
export 'src/models/interaction.dart';
export 'src/models/invite.dart';
export 'src/models/member.dart';
export 'src/models/message.dart';
export 'src/models/permission.dart';
export 'src/models/permission_overwrite.dart';
export 'src/models/plugin_manifest.dart';
export 'src/models/presence.dart';
export 'src/models/reaction.dart';
export 'src/models/report_category.dart';
export 'src/models/role.dart';
export 'src/models/sound.dart';
export 'src/models/space.dart';
export 'src/models/user.dart';
export 'src/models/voice_server_update.dart';
export 'src/models/voice_state.dart';

// Utils
export 'src/utils/cdn.dart';
export 'src/utils/host.dart';
export 'src/utils/qualified_id.dart';
export 'src/utils/snowflake.dart';
