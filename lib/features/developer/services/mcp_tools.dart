import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/developer/services/mcp_home_bridge.dart';
import 'package:bonfire/features/events/controllers/connection.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A tool handler: takes the MCP call arguments and returns the result map
/// (`{ok: true, ...}` on success, `{error: ...}` on failure). Mirrors the
/// reference client's test-API endpoints.
typedef McpToolHandler = Future<Map<String, dynamic>> Function(
    Map<String, dynamic> args);

/// One registered MCP tool: its name, permission group, advertised description
/// and JSON input schema, plus the handler that runs it.
class McpToolDef {
  const McpToolDef({
    required this.name,
    required this.group,
    required this.description,
    required this.inputSchema,
    required this.handler,
  });

  final String name;
  final String group;
  final String description;
  final Map<String, dynamic> inputSchema;
  final McpToolHandler handler;
}

/// One entry in the MCP server's in-memory activity log.
class McpActivity {
  McpActivity(this.tool, this.ok) : time = DateTime.now();

  final String tool;
  final bool ok;
  final DateTime time;
}

/// The Dart port of the reference client's "Client Test API": the set of tools
/// the local MCP server exposes (read / navigate / message / moderate / voice).
///
/// Read tools pull from the Riverpod caches (falling back to a direct REST fetch
/// where the cache may be cold); message/moderate tools call accordkit REST
/// directly; voice tools drive [VoiceController]; navigate tools delegate to the
/// [mcpHomeBridge] (which the home screen fulfils). Web-safe — holds no
/// `dart:io` dependency.
class McpTools {
  McpTools(this.ref) {
    _registerAll();
  }

  final Ref ref;
  final Map<String, McpToolDef> _tools = {};

  /// Every registered tool, keyed by name.
  Map<String, McpToolDef> get tools => _tools;

  AccordClient? get _client => ref.accordClient;

  Map<String, dynamic> get _notConnected => {'error': 'Not connected'};

  Map<String, dynamic> _restError(RestResult r) =>
      {'error': r.error?.message ?? 'Request failed', '_status': r.statusCode};

  // ── Registration ────────────────────────────────────────────────────────

  void _register(String name, String group, String description,
      Map<String, dynamic> inputSchema, McpToolHandler handler) {
    _tools[name] = McpToolDef(
      name: name,
      group: group,
      description: description,
      inputSchema: inputSchema.isEmpty
          ? {'type': 'object', 'properties': <String, dynamic>{}}
          : inputSchema,
      handler: handler,
    );
  }

  Map<String, dynamic> _schema(Map<String, String> props,
      [List<String> required = const []]) {
    final properties = {
      for (final e in props.entries) e.key: {'type': e.value},
    };
    final s = <String, dynamic>{'type': 'object', 'properties': properties};
    if (required.isNotEmpty) s['required'] = required;
    return s;
  }

  void _registerAll() {
    // ── read ──────────────────────────────────────────────────────────────
    _register('get_current_state', 'read',
        'Get current client state (space, channel, voice)', {}, _getState);
    _register('list_spaces', 'read', 'List all spaces the user is in', {},
        _listSpaces);
    _register('list_channels', 'read', 'List channels in a space',
        _schema({'space_id': 'string'}, ['space_id']), _listChannels);
    _register('list_members', 'read', 'List members of a space',
        _schema({'space_id': 'string'}, ['space_id']), _listMembers);
    _register(
        'list_messages',
        'read',
        'List recent messages in a channel',
        _schema({'channel_id': 'string', 'limit': 'integer'}, ['channel_id']),
        _listMessages);
    _register(
        'search_messages',
        'read',
        'Search messages in a space',
        _schema({'query': 'string', 'space_id': 'string'}, ['query']),
        _searchMessages);
    _register('get_user', 'read', 'Get user details by ID',
        _schema({'user_id': 'string'}, ['user_id']), _getUser);
    _register('get_space', 'read', 'Get space details by ID',
        _schema({'space_id': 'string'}, ['space_id']), _getSpace);
    _register('list_roles', 'read', 'List roles in a space',
        _schema({'space_id': 'string'}, ['space_id']), _listRoles);
    _register(
        'list_permissions',
        'read',
        'List all known permission identifiers and their descriptions',
        {},
        _listPermissions);

    // ── navigate ────────────────────────────────────────────────────────────
    _register('select_space', 'navigate', 'Switch to a space',
        _schema({'space_id': 'string'}, ['space_id']), _selectSpace);
    _register('select_channel', 'navigate', 'Switch to a channel',
        _schema({'channel_id': 'string'}, ['channel_id']), _selectChannel);
    _register('open_dm', 'navigate', 'Open direct messages', {}, _openDm);
    _register('open_settings', 'navigate', 'Open app settings',
        _schema({'page': 'string'}), _openSettings);
    _register('open_discovery', 'navigate', 'Open server discovery', {},
        _openDiscovery);
    _register('open_thread', 'navigate', 'Open a message thread',
        _schema({'message_id': 'string'}, ['message_id']), _openThread);
    _register('open_voice_view', 'navigate', 'Open voice/video view', {},
        _openVoiceView);
    _register('toggle_member_list', 'navigate', 'Toggle member list visibility',
        {}, _toggleMemberList);
    _register(
        'toggle_search', 'navigate', 'Toggle search panel', {}, _toggleSearch);
    _register(
        'set_theme',
        'navigate',
        'Apply a theme preset (dark/midnight/light/nord/monokai/solarized)',
        _schema({'preset': 'string'}, ['preset']),
        _setTheme);

    // ── message ─────────────────────────────────────────────────────────────
    _register(
        'send_message',
        'message',
        'Send a message to a channel',
        _schema({
          'channel_id': 'string',
          'content': 'string',
          'reply_to': 'string',
        }, [
          'channel_id',
          'content'
        ]),
        _sendMessage);
    _register(
        'edit_message',
        'message',
        'Edit a message (must be in a loaded channel)',
        _schema({'message_id': 'string', 'content': 'string'},
            ['message_id', 'content']),
        _editMessage);
    _register('delete_message', 'message',
        'Delete a message (must be in a loaded channel)',
        _schema({'message_id': 'string'}, ['message_id']), _deleteMessage);
    _register(
        'add_reaction',
        'message',
        'Add a reaction to a message',
        _schema({
          'channel_id': 'string',
          'message_id': 'string',
          'emoji': 'string',
        }, [
          'channel_id',
          'message_id',
          'emoji'
        ]),
        _addReaction);

    // ── moderate ────────────────────────────────────────────────────────────
    _register(
        'kick_member',
        'moderate',
        'Kick a member from a space',
        _schema({'space_id': 'string', 'user_id': 'string'},
            ['space_id', 'user_id']),
        _kickMember);
    _register(
        'ban_user',
        'moderate',
        'Ban a user from a space',
        _schema({
          'space_id': 'string',
          'user_id': 'string',
          'reason': 'string',
        }, [
          'space_id',
          'user_id'
        ]),
        _banUser);
    _register(
        'unban_user',
        'moderate',
        'Unban a user from a space',
        _schema({'space_id': 'string', 'user_id': 'string'},
            ['space_id', 'user_id']),
        _unbanUser);
    _register(
        'timeout_member',
        'moderate',
        'Timeout a member in a space (duration in seconds)',
        _schema({
          'space_id': 'string',
          'user_id': 'string',
          'duration': 'integer',
        }, [
          'space_id',
          'user_id',
          'duration'
        ]),
        _timeoutMember);

    // ── manage ────────────────────────────────────────────────────────────
    _register(
        'create_role',
        'manage',
        'Create a role in a space (permissions is an array of permission ids)',
        _schema({
          'space_id': 'string',
          'name': 'string',
          'color': 'integer',
          'permissions': 'array',
          'hoist': 'boolean',
          'mentionable': 'boolean',
        }, [
          'space_id',
          'name'
        ]),
        _createRole);
    _register(
        'update_role',
        'manage',
        'Update a role; only the provided fields change. permissions replaces '
            'the role\'s full permission set',
        _schema({
          'space_id': 'string',
          'role_id': 'string',
          'name': 'string',
          'color': 'integer',
          'permissions': 'array',
          'position': 'integer',
          'hoist': 'boolean',
          'mentionable': 'boolean',
        }, [
          'space_id',
          'role_id'
        ]),
        _updateRole);
    _register(
        'delete_role',
        'manage',
        'Delete a role from a space',
        _schema({'space_id': 'string', 'role_id': 'string'},
            ['space_id', 'role_id']),
        _deleteRole);
    _register(
        'add_member_role',
        'manage',
        'Assign a role to a member',
        _schema({
          'space_id': 'string',
          'user_id': 'string',
          'role_id': 'string',
        }, [
          'space_id',
          'user_id',
          'role_id'
        ]),
        _addMemberRole);
    _register(
        'remove_member_role',
        'manage',
        'Remove a role from a member',
        _schema({
          'space_id': 'string',
          'user_id': 'string',
          'role_id': 'string',
        }, [
          'space_id',
          'user_id',
          'role_id'
        ]),
        _removeMemberRole);
    _register(
        'list_channel_permissions',
        'manage',
        'List a channel\'s permission overwrites (per-role and per-member '
            'allow/deny rules)',
        _schema({'channel_id': 'string'}, ['channel_id']),
        _listChannelPermissions);
    _register(
        'set_channel_permission',
        'manage',
        'Create or update a channel permission overwrite for a role or member. '
            'target_type is "role" or "member"; target_id is the role/user id. '
            'allow and deny are arrays of permission ids (see list_permissions)',
        _schema({
          'channel_id': 'string',
          'target_id': 'string',
          'target_type': 'string',
          'allow': 'array',
          'deny': 'array',
        }, [
          'channel_id',
          'target_id',
          'target_type'
        ]),
        _setChannelPermission);
    _register(
        'delete_channel_permission',
        'manage',
        'Remove a channel permission overwrite for a role or member',
        _schema({'channel_id': 'string', 'target_id': 'string'},
            ['channel_id', 'target_id']),
        _deleteChannelPermission);

    // ── voice ─────────────────────────────────────────────────────────────
    _register('join_voice_channel', 'voice', 'Join a voice channel',
        _schema({'channel_id': 'string'}, ['channel_id']), _joinVoice);
    _register('leave_voice', 'voice', 'Leave the current voice channel', {},
        _leaveVoice);
    _register('toggle_mute', 'voice', 'Toggle microphone mute', {}, _toggleMute);
    _register(
        'toggle_deafen', 'voice', 'Toggle audio deafen', {}, _toggleDeafen);
  }

  // ── read handlers ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _getState(Map<String, dynamic> args) async {
    final connections = ref.read(connectionsControllerProvider);
    final spaces = ref.read(spacesControllerProvider);
    final voice = ref.read(voiceControllerProvider);
    final session = ref.read(accordAuthProvider
        .select((s) => s is AccordAuthLoggedIn ? s.session : null));
    final connected = connections.connections
        .where((c) => c.status == ConnectionStatus.connected)
        .length;
    return {
      'ok': true,
      'space_id': mcpHomeBridge.currentSpaceId ?? '',
      'channel_id': mcpHomeBridge.currentChannelId ?? '',
      'member_list_visible': mcpHomeBridge.memberListVisible,
      'voice_channel_id': voice.channelId ?? '',
      'voice_self_mute': voice.selfMute,
      'voice_self_deaf': voice.selfDeaf,
      'connected_servers': connected,
      'space_count': spaces?.length ?? 0,
      'user_id': session?.userId ?? '',
      'username': session?.username ?? '',
    };
  }

  Future<Map<String, dynamic>> _listSpaces(Map<String, dynamic> args) async {
    var spaces = ref.read(spacesControllerProvider);
    if (spaces == null) {
      final client = _client;
      if (client == null) return _notConnected;
      final r = await client.users.listSpaces();
      if (!r.ok) return _restError(r);
      spaces = (r.data as List? ?? const []).whereType<AccordSpace>().toList();
    }
    return {'ok': true, 'spaces': [for (final s in spaces) _spaceBrief(s)]};
  }

  Future<Map<String, dynamic>> _getSpace(Map<String, dynamic> args) async {
    final id = (args['space_id'] ?? '').toString();
    if (id.isEmpty) return {'error': 'space_id is required'};
    var space =
        ref.read(spacesControllerProvider)?.firstWhereOrNull((s) => s.id == id);
    if (space == null) {
      final client = _client;
      if (client == null) return _notConnected;
      final r = await client.spaces.fetch(id);
      if (r.ok && r.data is AccordSpace) space = r.data as AccordSpace;
    }
    if (space == null) return {'error': 'Space not found: $id'};
    return {'ok': true, 'space': _spaceFull(space)};
  }

  Future<Map<String, dynamic>> _listChannels(Map<String, dynamic> args) async {
    final id = (args['space_id'] ?? '').toString();
    if (id.isEmpty) return {'error': 'space_id is required'};
    final client = _client;
    if (client == null) return _notConnected;
    final r = await client.spaces.listChannels(id);
    if (!r.ok) return _restError(r);
    final channels = (r.data as List? ?? const []).whereType<AccordChannel>();
    return {
      'ok': true,
      'channels': [for (final c in channels) _channelBrief(c)],
    };
  }

  Future<Map<String, dynamic>> _listMembers(Map<String, dynamic> args) async {
    final id = (args['space_id'] ?? '').toString();
    if (id.isEmpty) return {'error': 'space_id is required'};
    final client = _client;
    if (client == null) return _notConnected;
    final r = await client.members.list(id, query: {'limit': 100});
    if (!r.ok) return _restError(r);
    final members = (r.data as List? ?? const []).whereType<AccordMember>();
    return {
      'ok': true,
      'members': [for (final m in members) _memberBrief(m)],
    };
  }

  Future<Map<String, dynamic>> _listMessages(Map<String, dynamic> args) async {
    final channelId = (args['channel_id'] ?? '').toString();
    if (channelId.isEmpty) return {'error': 'channel_id is required'};
    final limit = _asInt(args['limit'], 50).clamp(1, 100);
    final client = _client;
    if (client == null) return _notConnected;
    final r = await client.messages.list(channelId, query: {'limit': limit});
    if (!r.ok) return _restError(r);
    // REST returns newest-first; present oldest-first like the reference.
    final messages =
        (r.data as List? ?? const []).whereType<AccordMessage>().toList();
    return {
      'ok': true,
      'messages': [for (final m in messages.reversed) _messageBrief(m)],
    };
  }

  Future<Map<String, dynamic>> _searchMessages(
      Map<String, dynamic> args) async {
    final query = (args['query'] ?? '').toString();
    if (query.isEmpty) return {'error': 'query is required'};
    final spaceId = (args['space_id'] ?? mcpHomeBridge.currentSpaceId ?? '')
        .toString();
    if (spaceId.isEmpty) return {'error': 'No space context for search'};
    final client = _client;
    if (client == null) return _notConnected;
    final r = await client.messages.search(spaceId, query);
    if (!r.ok) return _restError(r);
    final messages = (r.data as List? ?? const []).whereType<AccordMessage>();
    return {
      'ok': true,
      'results': [for (final m in messages) _messageBrief(m)],
    };
  }

  Future<Map<String, dynamic>> _getUser(Map<String, dynamic> args) async {
    final id = (args['user_id'] ?? '').toString();
    if (id.isEmpty) return {'error': 'user_id is required'};
    final client = _client;
    if (client == null) return _notConnected;
    final r = await client.users.fetch(id);
    if (!r.ok) return _restError(r);
    if (r.data is! AccordUser) return {'error': 'User not found: $id'};
    return {'ok': true, 'user': _userBrief(r.data as AccordUser)};
  }

  Future<Map<String, dynamic>> _listRoles(Map<String, dynamic> args) async {
    final id = (args['space_id'] ?? '').toString();
    if (id.isEmpty) return {'error': 'space_id is required'};
    final client = _client;
    if (client == null) return _notConnected;
    final r = await client.roles.list(id);
    if (!r.ok) return _restError(r);
    final roles = (r.data as List? ?? const []).whereType<AccordRole>();
    return {'ok': true, 'roles': [for (final role in roles) _roleFull(role)]};
  }

  Future<Map<String, dynamic>> _listPermissions(Map<String, dynamic> args) =>
      Future.value({
        'ok': true,
        'permissions': [
          for (final p in AccordPermission.all())
            {'id': p, 'description': AccordPermission.description(p)},
        ],
      });

  // ── navigate handlers ───────────────────────────────────────────────────

  Future<Map<String, dynamic>> _selectSpace(Map<String, dynamic> args) async {
    final id = (args['space_id'] ?? '').toString();
    if (id.isEmpty) return {'error': 'space_id is required'};
    final serverKey = _serverKeyForSpace(id);
    if (serverKey == null) return {'error': 'Space not found: $id'};
    return mcpHomeBridge
        .invoke('select_space', {'space_id': id, 'server_key': serverKey});
  }

  Future<Map<String, dynamic>> _selectChannel(Map<String, dynamic> args) async {
    final channelId = (args['channel_id'] ?? '').toString();
    if (channelId.isEmpty) return {'error': 'channel_id is required'};
    final spaceId = _spaceForChannel(channelId);
    if (spaceId == null) return {'error': 'Channel not found: $channelId'};
    return mcpHomeBridge.invoke(
        'select_channel', {'channel_id': channelId, 'space_id': spaceId});
  }

  Future<Map<String, dynamic>> _openDm(Map<String, dynamic> args) =>
      mcpHomeBridge.invoke('open_dm', const {});

  Future<Map<String, dynamic>> _openSettings(Map<String, dynamic> args) =>
      mcpHomeBridge
          .invoke('open_settings', {'page': (args['page'] ?? '').toString()});

  Future<Map<String, dynamic>> _openDiscovery(Map<String, dynamic> args) =>
      mcpHomeBridge.invoke('open_discovery', const {});

  Future<Map<String, dynamic>> _openThread(Map<String, dynamic> args) async {
    final messageId = (args['message_id'] ?? '').toString();
    if (messageId.isEmpty) return {'error': 'message_id is required'};
    final channelId = _channelForMessage(messageId);
    if (channelId == null) {
      return {'error': 'Message not found in a loaded channel'};
    }
    return mcpHomeBridge.invoke(
        'open_thread', {'message_id': messageId, 'channel_id': channelId});
  }

  Future<Map<String, dynamic>> _openVoiceView(Map<String, dynamic> args) =>
      mcpHomeBridge.invoke('open_voice_view', const {});

  Future<Map<String, dynamic>> _toggleMemberList(Map<String, dynamic> args) =>
      mcpHomeBridge.invoke('toggle_member_list', const {});

  Future<Map<String, dynamic>> _toggleSearch(Map<String, dynamic> args) =>
      mcpHomeBridge.invoke('toggle_search', const {});

  Future<Map<String, dynamic>> _setTheme(Map<String, dynamic> args) async {
    final preset = (args['preset'] ?? '').toString();
    if (preset.isEmpty) return {'error': 'preset is required'};
    final match = AppThemePreset.values.firstWhereOrNull((p) =>
        p.name == preset || p.label.toLowerCase() == preset.toLowerCase());
    if (match == null) {
      final valid = AppThemePreset.values.map((p) => p.name).join(', ');
      return {'error': 'Unknown preset: $preset. Valid: $valid'};
    }
    ref.read(settingsControllerProvider.notifier).setThemePreset(match);
    return {'ok': true, 'preset': match.name};
  }

  // ── message handlers ────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _sendMessage(Map<String, dynamic> args) async {
    final channelId = (args['channel_id'] ?? '').toString();
    final content = (args['content'] ?? '').toString();
    if (channelId.isEmpty) return {'error': 'channel_id is required'};
    if (content.isEmpty) return {'error': 'content is required'};
    final client = _client;
    if (client == null) return _notConnected;
    final data = <String, dynamic>{'content': content};
    final replyTo = (args['reply_to'] ?? '').toString();
    if (replyTo.isNotEmpty) data['reply_to'] = replyTo;
    final r = await client.messages.create(channelId, data);
    return r.ok ? {'ok': true} : _restError(r);
  }

  Future<Map<String, dynamic>> _editMessage(Map<String, dynamic> args) async {
    final messageId = (args['message_id'] ?? '').toString();
    final content = (args['content'] ?? '').toString();
    if (messageId.isEmpty) return {'error': 'message_id is required'};
    if (content.isEmpty) return {'error': 'content is required'};
    final client = _client;
    if (client == null) return _notConnected;
    final channelId = _channelForMessage(messageId);
    if (channelId == null) {
      return {'error': 'Message not found in a loaded channel'};
    }
    final r =
        await client.messages.edit(channelId, messageId, {'content': content});
    return r.ok ? {'ok': true} : _restError(r);
  }

  Future<Map<String, dynamic>> _deleteMessage(Map<String, dynamic> args) async {
    final messageId = (args['message_id'] ?? '').toString();
    if (messageId.isEmpty) return {'error': 'message_id is required'};
    final client = _client;
    if (client == null) return _notConnected;
    final channelId = _channelForMessage(messageId);
    if (channelId == null) {
      return {'error': 'Message not found in a loaded channel'};
    }
    final r = await client.messages.delete(channelId, messageId);
    return r.ok ? {'ok': true} : _restError(r);
  }

  Future<Map<String, dynamic>> _addReaction(Map<String, dynamic> args) async {
    final channelId = (args['channel_id'] ?? '').toString();
    final messageId = (args['message_id'] ?? '').toString();
    final emoji = (args['emoji'] ?? '').toString();
    if (channelId.isEmpty) return {'error': 'channel_id is required'};
    if (messageId.isEmpty) return {'error': 'message_id is required'};
    if (emoji.isEmpty) return {'error': 'emoji is required'};
    final client = _client;
    if (client == null) return _notConnected;
    final r = await client.reactions.add(channelId, messageId, emoji);
    return r.ok ? {'ok': true} : _restError(r);
  }

  // ── moderate handlers ───────────────────────────────────────────────────

  Future<Map<String, dynamic>> _kickMember(Map<String, dynamic> args) async {
    final spaceId = (args['space_id'] ?? '').toString();
    final userId = (args['user_id'] ?? '').toString();
    if (spaceId.isEmpty) return {'error': 'space_id is required'};
    if (userId.isEmpty) return {'error': 'user_id is required'};
    final client = _client;
    if (client == null) return _notConnected;
    final r = await client.members.kick(spaceId, userId);
    return r.ok ? {'ok': true} : _restError(r);
  }

  Future<Map<String, dynamic>> _banUser(Map<String, dynamic> args) async {
    final spaceId = (args['space_id'] ?? '').toString();
    final userId = (args['user_id'] ?? '').toString();
    if (spaceId.isEmpty) return {'error': 'space_id is required'};
    if (userId.isEmpty) return {'error': 'user_id is required'};
    final client = _client;
    if (client == null) return _notConnected;
    final reason = (args['reason'] ?? '').toString();
    final data = reason.isEmpty ? const <String, dynamic>{} : {'reason': reason};
    final r = await client.bans.create(spaceId, userId, data: data);
    return r.ok ? {'ok': true} : _restError(r);
  }

  Future<Map<String, dynamic>> _unbanUser(Map<String, dynamic> args) async {
    final spaceId = (args['space_id'] ?? '').toString();
    final userId = (args['user_id'] ?? '').toString();
    if (spaceId.isEmpty) return {'error': 'space_id is required'};
    if (userId.isEmpty) return {'error': 'user_id is required'};
    final client = _client;
    if (client == null) return _notConnected;
    final r = await client.bans.remove(spaceId, userId);
    return r.ok ? {'ok': true} : _restError(r);
  }

  Future<Map<String, dynamic>> _timeoutMember(Map<String, dynamic> args) async {
    final spaceId = (args['space_id'] ?? '').toString();
    final userId = (args['user_id'] ?? '').toString();
    final duration = _asInt(args['duration'], 0);
    if (spaceId.isEmpty) return {'error': 'space_id is required'};
    if (userId.isEmpty) return {'error': 'user_id is required'};
    if (duration <= 0) return {'error': 'duration is required (seconds)'};
    final client = _client;
    if (client == null) return _notConnected;
    final until = DateTime.now()
        .toUtc()
        .add(Duration(seconds: duration))
        .toIso8601String();
    final r = await client.members
        .update(spaceId, userId, {'communication_disabled_until': until});
    return r.ok ? {'ok': true} : _restError(r);
  }

  // ── manage handlers ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _createRole(Map<String, dynamic> args) async {
    final spaceId = (args['space_id'] ?? '').toString();
    final name = (args['name'] ?? '').toString();
    if (spaceId.isEmpty) return {'error': 'space_id is required'};
    final client = _client;
    if (client == null) return _notConnected;
    if (name.isEmpty) return {'error': 'name is required'};
    final data = <String, dynamic>{'name': name};
    if (args.containsKey('color')) data['color'] = _asInt(args['color'], 0);
    final perms = _permList(args['permissions']);
    if (perms != null) data['permissions'] = perms;
    if (args.containsKey('hoist')) data['hoist'] = _asBool(args['hoist']);
    if (args.containsKey('mentionable')) {
      data['mentionable'] = _asBool(args['mentionable']);
    }
    final r = await client.roles.create(spaceId, data);
    if (!r.ok) return _restError(r);
    return {
      'ok': true,
      if (r.data is AccordRole) 'role': _roleFull(r.data as AccordRole),
    };
  }

  Future<Map<String, dynamic>> _updateRole(Map<String, dynamic> args) async {
    final spaceId = (args['space_id'] ?? '').toString();
    final roleId = (args['role_id'] ?? '').toString();
    if (spaceId.isEmpty) return {'error': 'space_id is required'};
    if (roleId.isEmpty) return {'error': 'role_id is required'};
    final data = <String, dynamic>{};
    if (args.containsKey('name')) {
      final name = (args['name'] ?? '').toString();
      if (name.isEmpty) return {'error': 'name cannot be empty'};
      data['name'] = name;
    }
    if (args.containsKey('color')) data['color'] = _asInt(args['color'], 0);
    final perms = _permList(args['permissions']);
    if (perms != null) data['permissions'] = perms;
    if (args.containsKey('position')) {
      data['position'] = _asInt(args['position'], 0);
    }
    if (args.containsKey('hoist')) data['hoist'] = _asBool(args['hoist']);
    if (args.containsKey('mentionable')) {
      data['mentionable'] = _asBool(args['mentionable']);
    }
    if (data.isEmpty) return {'error': 'No fields to update'};
    final client = _client;
    if (client == null) return _notConnected;
    final r = await client.roles.update(spaceId, roleId, data);
    if (!r.ok) return _restError(r);
    return {
      'ok': true,
      if (r.data is AccordRole) 'role': _roleFull(r.data as AccordRole),
    };
  }

  Future<Map<String, dynamic>> _deleteRole(Map<String, dynamic> args) async {
    final spaceId = (args['space_id'] ?? '').toString();
    final roleId = (args['role_id'] ?? '').toString();
    if (spaceId.isEmpty) return {'error': 'space_id is required'};
    if (roleId.isEmpty) return {'error': 'role_id is required'};
    final client = _client;
    if (client == null) return _notConnected;
    final r = await client.roles.delete(spaceId, roleId);
    return r.ok ? {'ok': true} : _restError(r);
  }

  Future<Map<String, dynamic>> _addMemberRole(Map<String, dynamic> args) async {
    final spaceId = (args['space_id'] ?? '').toString();
    final userId = (args['user_id'] ?? '').toString();
    final roleId = (args['role_id'] ?? '').toString();
    if (spaceId.isEmpty) return {'error': 'space_id is required'};
    if (userId.isEmpty) return {'error': 'user_id is required'};
    if (roleId.isEmpty) return {'error': 'role_id is required'};
    final client = _client;
    if (client == null) return _notConnected;
    final r = await client.members.addRole(spaceId, userId, roleId);
    return r.ok ? {'ok': true} : _restError(r);
  }

  Future<Map<String, dynamic>> _removeMemberRole(
      Map<String, dynamic> args) async {
    final spaceId = (args['space_id'] ?? '').toString();
    final userId = (args['user_id'] ?? '').toString();
    final roleId = (args['role_id'] ?? '').toString();
    if (spaceId.isEmpty) return {'error': 'space_id is required'};
    if (userId.isEmpty) return {'error': 'user_id is required'};
    if (roleId.isEmpty) return {'error': 'role_id is required'};
    final client = _client;
    if (client == null) return _notConnected;
    final r = await client.members.removeRole(spaceId, userId, roleId);
    return r.ok ? {'ok': true} : _restError(r);
  }

  Future<Map<String, dynamic>> _listChannelPermissions(
      Map<String, dynamic> args) async {
    final channelId = (args['channel_id'] ?? '').toString();
    if (channelId.isEmpty) return {'error': 'channel_id is required'};
    final client = _client;
    if (client == null) return _notConnected;
    final r = await client.channels.listOverwrites(channelId);
    if (!r.ok) return _restError(r);
    final raw = r.data is List ? r.data as List : const [];
    return {
      'ok': true,
      'overwrites': [for (final o in raw) _overwriteBrief(o)],
    };
  }

  Future<Map<String, dynamic>> _setChannelPermission(
      Map<String, dynamic> args) async {
    final channelId = (args['channel_id'] ?? '').toString();
    final targetId = (args['target_id'] ?? '').toString();
    final type = (args['target_type'] ?? '').toString().toLowerCase();
    if (channelId.isEmpty) return {'error': 'channel_id is required'};
    if (targetId.isEmpty) return {'error': 'target_id is required'};
    if (type != 'role' && type != 'member') {
      return {'error': 'target_type must be "role" or "member"'};
    }
    final client = _client;
    if (client == null) return _notConnected;
    final data = <String, dynamic>{
      'type': type,
      'allow': _permList(args['allow']) ?? const <String>[],
      'deny': _permList(args['deny']) ?? const <String>[],
    };
    final r = await client.channels.upsertOverwrite(channelId, targetId, data);
    return r.ok ? {'ok': true} : _restError(r);
  }

  Future<Map<String, dynamic>> _deleteChannelPermission(
      Map<String, dynamic> args) async {
    final channelId = (args['channel_id'] ?? '').toString();
    final targetId = (args['target_id'] ?? '').toString();
    if (channelId.isEmpty) return {'error': 'channel_id is required'};
    if (targetId.isEmpty) return {'error': 'target_id is required'};
    final client = _client;
    if (client == null) return _notConnected;
    final r = await client.channels.deleteOverwrite(channelId, targetId);
    return r.ok ? {'ok': true} : _restError(r);
  }

  // ── voice handlers ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _joinVoice(Map<String, dynamic> args) async {
    final channelId = (args['channel_id'] ?? '').toString();
    if (channelId.isEmpty) return {'error': 'channel_id is required'};
    final spaceId = _spaceForChannel(channelId);
    if (spaceId == null) return {'error': 'Channel not found: $channelId'};
    await ref.read(voiceControllerProvider.notifier).join(channelId, spaceId);
    final error = ref.read(voiceControllerProvider).error;
    if (error != null) return {'error': error};
    return {'ok': true, 'channel_id': channelId};
  }

  Future<Map<String, dynamic>> _leaveVoice(Map<String, dynamic> args) async {
    await ref.read(voiceControllerProvider.notifier).leave();
    return {'ok': true};
  }

  Future<Map<String, dynamic>> _toggleMute(Map<String, dynamic> args) async {
    final notifier = ref.read(voiceControllerProvider.notifier);
    if (!ref.read(voiceControllerProvider).isConnected) {
      return {'error': 'Not in a voice channel'};
    }
    notifier.toggleMute();
    return {'ok': true, 'muted': ref.read(voiceControllerProvider).selfMute};
  }

  Future<Map<String, dynamic>> _toggleDeafen(Map<String, dynamic> args) async {
    final notifier = ref.read(voiceControllerProvider.notifier);
    if (!ref.read(voiceControllerProvider).isConnected) {
      return {'error': 'Not in a voice channel'};
    }
    notifier.toggleDeafen();
    return {'ok': true, 'deafened': ref.read(voiceControllerProvider).selfDeaf};
  }

  // ── lookups ─────────────────────────────────────────────────────────────

  /// The connection key owning [spaceId], scanning every connected server's
  /// cached space list (falling back to the active key when the shared spaces
  /// controller has it but the rail cache hasn't caught up).
  String? _serverKeyForSpace(String spaceId) {
    final connections = ref.read(connectionsControllerProvider);
    for (final c in connections.connections) {
      if (c.spaces.any((s) => s.id == spaceId)) return c.key;
    }
    final spaces = ref.read(spacesControllerProvider);
    if (spaces != null && spaces.any((s) => s.id == spaceId)) {
      return connections.activeKey;
    }
    return null;
  }

  /// The space owning [channelId], scanning loaded channel lists.
  String? _spaceForChannel(String channelId) {
    final spaces = ref.read(spacesControllerProvider) ?? const [];
    for (final s in spaces) {
      final channels = ref.read(accordChannelsControllerProvider(s.id));
      if (channels != null && channels.any((c) => c.id == channelId)) {
        return s.id;
      }
    }
    return null;
  }

  /// The channel of a loaded message [messageId] (only channels the UI has
  /// opened are searchable — mirrors the reference's in-memory message cache).
  String? _channelForMessage(String messageId) {
    for (final channelId in activeMessageChannels) {
      final messages = ref.read(accordMessagesControllerProvider(channelId));
      if (messages != null && messages.any((m) => m.id == messageId)) {
        return channelId;
      }
    }
    return null;
  }

  // ── serializers (curated, snake_case — mirror the reference shapes) ────────

  Map<String, dynamic> _spaceBrief(AccordSpace s) => {
        'id': s.id,
        'name': s.name,
        'owner_id': s.ownerId,
        'member_count': s.memberCount ?? 0,
      };

  Map<String, dynamic> _spaceFull(AccordSpace s) => {
        'id': s.id,
        'name': s.name,
        'slug': s.slug,
        'description': s.description ?? '',
        'owner_id': s.ownerId,
        'member_count': s.memberCount ?? 0,
        'public': s.public,
        'role_count': s.roles.length,
        'rules_channel_id': s.rulesChannelId ?? '',
      };

  Map<String, dynamic> _channelBrief(AccordChannel c) => {
        'id': c.id,
        'name': c.name ?? '',
        'type': c.type,
        'parent_id': c.parentId ?? '',
        'topic': c.topic ?? '',
        'position': c.position ?? 0,
        'nsfw': c.nsfw,
      };

  Map<String, dynamic> _memberBrief(AccordMember m) => {
        'id': m.userId,
        'username': m.user?.username ?? '',
        'display_name': m.user?.displayName ?? m.nickname ?? '',
        'roles': m.roles,
      };

  Map<String, dynamic> _roleFull(AccordRole r) => {
        'id': r.id,
        'name': r.name,
        'color': r.color,
        'hoist': r.hoist,
        'position': r.position,
        'permissions': [for (final p in r.permissions) p.toString()],
        'managed': r.managed,
        'mentionable': r.mentionable,
      };

  Map<String, dynamic> _overwriteBrief(Object? o) {
    final m = o is Map ? o : const {};
    return {
      'id': (m['id'] ?? '').toString(),
      'type': (m['type'] ?? 'role').toString(),
      'allow': [for (final p in (m['allow'] as List? ?? const [])) p.toString()],
      'deny': [for (final p in (m['deny'] as List? ?? const [])) p.toString()],
    };
  }

  Map<String, dynamic> _messageBrief(AccordMessage m) => {
        'id': m.id,
        'content': m.content,
        'author_id': m.authorId,
        'channel_id': m.channelId,
        'timestamp': m.timestamp,
        'edited': m.editedAt != null,
        'reply_to': m.replyTo ?? '',
        'pinned': m.pinned,
      };

  Map<String, dynamic> _userBrief(AccordUser u) => {
        'id': u.id,
        'username': u.username,
        'display_name': u.displayName ?? '',
        'avatar': u.avatar ?? '',
        'is_admin': u.isAdmin,
        'bot': u.bot,
      };

  int _asInt(Object? v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? fallback;
  }

  bool _asBool(Object? v) {
    if (v is bool) return v;
    return '$v'.toLowerCase() == 'true';
  }

  /// Coerces an arg into a list of permission id strings, or null when the
  /// caller didn't supply a list (so the field is left untouched on update).
  List<String>? _permList(Object? v) {
    if (v is List) return [for (final e in v) e.toString()];
    return null;
  }
}
