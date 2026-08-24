part of '../mcp_tools.dart';

extension _McpToolCatalog on McpTools {
  void _registerAll() {
    // ── read ──────────────────────────────────────────────────────────────
    _register(
      'get_current_state',
      'read',
      'Get current client state (space, channel, voice)',
      {},
      _getState,
    );
    _register(
      'list_spaces',
      'read',
      'List all spaces the user is in',
      {},
      _listSpaces,
    );
    _register(
      'list_channels',
      'read',
      'List channels in a space',
      _schema({'space_id': 'string'}, ['space_id']),
      _listChannels,
    );
    _register(
      'list_members',
      'read',
      'List members of a space',
      _schema({'space_id': 'string'}, ['space_id']),
      _listMembers,
    );
    _register(
      'list_messages',
      'read',
      'List recent messages in a channel',
      _schema({'channel_id': 'string', 'limit': 'integer'}, ['channel_id']),
      _listMessages,
    );
    _register(
      'search_messages',
      'read',
      'Search messages in a space',
      _schema({'query': 'string', 'space_id': 'string'}, ['query']),
      _searchMessages,
    );
    _register(
      'list_voice_states',
      'read',
      'List who is currently in a voice channel',
      _schema({'channel_id': 'string'}, ['channel_id']),
      _listVoiceStates,
    );
    _register(
      'get_user',
      'read',
      'Get user details by ID',
      _schema({'user_id': 'string'}, ['user_id']),
      _getUser,
    );
    _register(
      'get_space',
      'read',
      'Get space details by ID',
      _schema({'space_id': 'string'}, ['space_id']),
      _getSpace,
    );
    _register(
      'list_roles',
      'read',
      'List roles in a space',
      _schema({'space_id': 'string'}, ['space_id']),
      _listRoles,
    );
    _register(
      'list_permissions',
      'read',
      'List all known permission identifiers and their descriptions',
      {},
      _listPermissions,
    );

    // ── navigate ────────────────────────────────────────────────────────────
    _register(
      'select_space',
      'navigate',
      'Switch to a space',
      _schema({'space_id': 'string'}, ['space_id']),
      _selectSpace,
    );
    _register(
      'select_channel',
      'navigate',
      'Switch to a channel',
      _schema({'channel_id': 'string'}, ['channel_id']),
      _selectChannel,
    );
    _register('open_dm', 'navigate', 'Open direct messages', {}, _openDm);
    _register(
      'open_settings',
      'navigate',
      'Open app settings',
      _schema({'page': 'string'}),
      _openSettings,
    );
    _register(
      'open_discovery',
      'navigate',
      'Open server discovery',
      {},
      _openDiscovery,
    );
    _register(
      'open_thread',
      'navigate',
      'Open a message thread',
      _schema({'message_id': 'string'}, ['message_id']),
      _openThread,
    );
    _register(
      'open_voice_view',
      'navigate',
      'Open voice/video view',
      {},
      _openVoiceView,
    );
    _register(
      'toggle_member_list',
      'navigate',
      'Toggle member list visibility',
      {},
      _toggleMemberList,
    );
    _register(
      'toggle_search',
      'navigate',
      'Toggle search panel',
      {},
      _toggleSearch,
    );
    _register(
      'set_theme',
      'navigate',
      'Apply a theme preset (dark/midnight/light/nord/monokai/solarized)',
      _schema({'preset': 'string'}, ['preset']),
      _setTheme,
    );

    // ── message ─────────────────────────────────────────────────────────────
    _register(
      'send_message',
      'message',
      'Send a message to a channel',
      _schema(
        {'channel_id': 'string', 'content': 'string', 'reply_to': 'string'},
        ['channel_id', 'content'],
      ),
      _sendMessage,
    );
    _register(
      'edit_message',
      'message',
      'Edit a message (must be in a loaded channel)',
      _schema(
        {'message_id': 'string', 'content': 'string'},
        ['message_id', 'content'],
      ),
      _editMessage,
    );
    _register(
      'delete_message',
      'message',
      'Delete a message (must be in a loaded channel)',
      _schema({'message_id': 'string'}, ['message_id']),
      _deleteMessage,
    );
    _register(
      'add_reaction',
      'message',
      'Add a reaction to a message',
      _schema(
        {'channel_id': 'string', 'message_id': 'string', 'emoji': 'string'},
        ['channel_id', 'message_id', 'emoji'],
      ),
      _addReaction,
    );

    // ── moderate ────────────────────────────────────────────────────────────
    _register(
      'kick_member',
      'moderate',
      'Kick a member from a space',
      _schema(
        {'space_id': 'string', 'user_id': 'string'},
        ['space_id', 'user_id'],
      ),
      _kickMember,
    );
    _register(
      'ban_user',
      'moderate',
      'Ban a user from a space',
      _schema(
        {'space_id': 'string', 'user_id': 'string', 'reason': 'string'},
        ['space_id', 'user_id'],
      ),
      _banUser,
    );
    _register(
      'unban_user',
      'moderate',
      'Unban a user from a space',
      _schema(
        {'space_id': 'string', 'user_id': 'string'},
        ['space_id', 'user_id'],
      ),
      _unbanUser,
    );
    _register(
      'timeout_member',
      'moderate',
      'Timeout a member in a space (duration in seconds)',
      _schema(
        {'space_id': 'string', 'user_id': 'string', 'duration': 'integer'},
        ['space_id', 'user_id', 'duration'],
      ),
      _timeoutMember,
    );

    // ── manage ────────────────────────────────────────────────────────────
    _register(
      'create_role',
      'manage',
      'Create a role in a space (permissions is an array of permission ids)',
      _schema(
        {
          'space_id': 'string',
          'name': 'string',
          'color': 'integer',
          'permissions': 'array',
          'hoist': 'boolean',
          'mentionable': 'boolean',
        },
        ['space_id', 'name'],
      ),
      _createRole,
    );
    _register(
      'update_role',
      'manage',
      'Update a role; only the provided fields change. permissions replaces '
          'the role\'s full permission set',
      _schema(
        {
          'space_id': 'string',
          'role_id': 'string',
          'name': 'string',
          'color': 'integer',
          'permissions': 'array',
          'position': 'integer',
          'hoist': 'boolean',
          'mentionable': 'boolean',
        },
        ['space_id', 'role_id'],
      ),
      _updateRole,
    );
    _register(
      'delete_role',
      'manage',
      'Delete a role from a space',
      _schema(
        {'space_id': 'string', 'role_id': 'string'},
        ['space_id', 'role_id'],
      ),
      _deleteRole,
    );
    _register(
      'add_member_role',
      'manage',
      'Assign a role to a member',
      _schema(
        {'space_id': 'string', 'user_id': 'string', 'role_id': 'string'},
        ['space_id', 'user_id', 'role_id'],
      ),
      _addMemberRole,
    );
    _register(
      'remove_member_role',
      'manage',
      'Remove a role from a member',
      _schema(
        {'space_id': 'string', 'user_id': 'string', 'role_id': 'string'},
        ['space_id', 'user_id', 'role_id'],
      ),
      _removeMemberRole,
    );
    _register(
      'list_channel_permissions',
      'manage',
      'List a channel\'s permission overwrites (per-role and per-member '
          'allow/deny rules)',
      _schema({'channel_id': 'string'}, ['channel_id']),
      _listChannelPermissions,
    );
    _register(
      'set_channel_permission',
      'manage',
      'Create or update a channel permission overwrite for a role or member. '
          'target_type is "role" or "member"; target_id is the role/user id. '
          'allow and deny are arrays of permission ids (see list_permissions)',
      _schema(
        {
          'channel_id': 'string',
          'target_id': 'string',
          'target_type': 'string',
          'allow': 'array',
          'deny': 'array',
        },
        ['channel_id', 'target_id', 'target_type'],
      ),
      _setChannelPermission,
    );
    _register(
      'delete_channel_permission',
      'manage',
      'Remove a channel permission overwrite for a role or member',
      _schema(
        {'channel_id': 'string', 'target_id': 'string'},
        ['channel_id', 'target_id'],
      ),
      _deleteChannelPermission,
    );

    // ── voice ─────────────────────────────────────────────────────────────
    _register(
      'join_voice_channel',
      'voice',
      'Join a voice channel',
      _schema({'channel_id': 'string'}, ['channel_id']),
      _joinVoice,
    );
    _register(
      'leave_voice',
      'voice',
      'Leave the current voice channel',
      {},
      _leaveVoice,
    );
    _register(
      'toggle_mute',
      'voice',
      'Toggle microphone mute',
      {},
      _toggleMute,
    );
    _register(
      'toggle_deafen',
      'voice',
      'Toggle audio deafen',
      {},
      _toggleDeafen,
    );
  }
}
