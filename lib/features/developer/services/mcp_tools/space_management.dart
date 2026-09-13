part of '../mcp_tools.dart';

const _managementId = {'type': 'string', 'minLength': 1};
const _managementNullableString = {
  'type': ['string', 'null'],
};
const _managementChannelFields = <String, dynamic>{
  'name': _managementId,
  'type': {
    'type': 'string',
    'enum': ['category', 'text', 'announcement', 'forum', 'voice'],
    'description':
        'Existing types may only change between text and announcement.',
  },
  'parent_id': {
    'type': ['string', 'null'],
    'minLength': 1,
    'description': 'Category ID in this space, or null to move to the root.',
  },
  'topic': _managementNullableString,
  'nsfw': {'type': 'boolean'},
  'rate_limit': {
    'type': 'integer',
    'minimum': 0,
    'maximum': AccordChannel.maxRateLimitSeconds,
    'description': 'Slowmode in seconds; zero disables it.',
  },
  'position': {'type': 'integer', 'minimum': 0},
};
const _managementImage = {
  'type': ['string', 'null'],
  'description':
      'Base64 image data URI (PNG, JPEG, GIF, WebP), or null to remove.',
};
const _managementSpaceFields = <String, dynamic>{
  'name': _managementId,
  'description': _managementNullableString,
  'icon': _managementImage,
  'banner': _managementImage,
  'verification_level': {
    'type': 'string',
    'enum': ['none', 'low', 'medium', 'high'],
  },
  'default_notifications': {
    'type': 'string',
    'enum': ['all', 'mentions'],
  },
  'nsfw_level': {
    'type': 'string',
    'enum': ['default', 'moderate', 'explicit'],
  },
  'explicit_content_filter': {
    'type': 'string',
    'enum': ['disabled', 'no_role', 'everyone'],
  },
  'public': {'type': 'boolean'},
  'allow_guest_access': {'type': 'boolean'},
  'rules_channel_id': {
    'type': ['string', 'null'],
    'minLength': 1,
  },
  'system_channel_id': {
    'type': ['string', 'null'],
    'minLength': 1,
  },
};

Map<String, dynamic> _managementSchema(
  Map<String, dynamic> properties,
  List<String> required,
) => {
  'type': 'object',
  'properties': properties,
  'required': required,
  'additionalProperties': false,
};

Map<String, dynamic> _managementError(
  String code,
  String message, {
  String? field,
}) => {'error': message, 'code': code, if (field != null) 'field': field};

/// Validate the advertised schema even for clients that skip JSON-schema
/// validation. Reject coercions and unknown fields instead of silently losing
/// settings (especially explicit nulls used to clear fields).
Map<String, dynamic>? _validateManagementValue(
  Object? value,
  Map schema, [
  String field = 'arguments',
]) {
  final types = schema['type'] is List
      ? schema['type'] as List
      : [schema['type']];
  final type = switch (value) {
    null => 'null',
    String() => 'string',
    bool() => 'boolean',
    int() => 'integer',
    List() => 'array',
    Map() => 'object',
    _ => 'unknown',
  };
  Map<String, dynamic> invalid(String message) =>
      _managementError('validation_error', message, field: field);
  if (!types.contains(type))
    return invalid('$field must be ${types.join(' or ')}');
  if (value == null) return null;
  if (schema['enum'] is List && !(schema['enum'] as List).contains(value)) {
    return invalid(
      '$field must be one of ${(schema['enum'] as List).join(', ')}',
    );
  }
  if (value is String && schema['minLength'] != null && value.trim().isEmpty) {
    return invalid('$field cannot be empty');
  }
  if (value is int &&
      ((schema['minimum'] != null && value < (schema['minimum'] as int)) ||
          (schema['maximum'] != null && value > (schema['maximum'] as int)))) {
    return invalid('$field is outside the allowed range');
  }
  if (value is Map) {
    final properties = schema['properties'] as Map;
    for (final key in schema['required'] as List? ?? const []) {
      if (!value.containsKey(key)) {
        return _managementError(
          'validation_error',
          '$key is required',
          field: '$field.$key',
        );
      }
    }
    for (final key in value.keys) {
      if (!properties.containsKey(key))
        return invalid('Unknown field: $field.$key');
      final error = _validateManagementValue(
        value[key],
        properties[key] as Map,
        '$field.$key',
      );
      if (error != null) return error;
    }
  }
  if (value is List) {
    if (value.isEmpty) return invalid('$field cannot be empty');
    for (var i = 0; i < value.length; i++) {
      final error = _validateManagementValue(
        value[i],
        schema['items'] as Map,
        '$field[$i]',
      );
      if (error != null) return error;
    }
  }
  return null;
}

extension _McpSpaceManagement on McpTools {
  void _registerSpaceManagement() {
    void register(
      String name,
      String description,
      Map<String, dynamic> schema,
      McpToolHandler handler,
    ) {
      _register(
        name,
        'space_management',
        '$description Uses the active server/account.',
        schema,
        (args) async {
          final error = _validateManagementValue(args, schema);
          if (error != null) return error;
          return handler(args);
        },
      );
    }

    register(
      'create_space',
      'Create a space.',
      _managementSchema(
        {
          'name': _managementId,
          'description': _managementNullableString,
          'icon': _managementImage,
        },
        ['name'],
      ),
      _createSpace,
    );
    register(
      'update_space',
      'Update only supplied space settings; null clears optional fields.',
      _managementSchema(
        {'space_id': _managementId, ..._managementSpaceFields},
        ['space_id'],
      ),
      _updateSpace,
    );
    register(
      'create_channel',
      'Create a category, text, announcement, forum or voice channel.',
      _managementSchema(
        {'space_id': _managementId, ..._managementChannelFields},
        ['space_id', 'name', 'type'],
      ),
      _createChannel,
    );
    register(
      'update_channel',
      'Update supplied channel fields. Type changes are limited to text/announcement.',
      _managementSchema(
        {
          'space_id': _managementId,
          'channel_id': _managementId,
          ..._managementChannelFields,
        },
        ['space_id', 'channel_id'],
      ),
      _updateChannel,
    );
    register(
      'delete_channel',
      'Permanently delete a channel. Requires confirm=true.',
      _managementSchema(
        {
          'space_id': _managementId,
          'channel_id': _managementId,
          'confirm': {
            'type': 'boolean',
            'enum': [true],
          },
        },
        ['space_id', 'channel_id', 'confirm'],
      ),
      _deleteChannel,
    );
    register(
      'reorder_channels',
      'Set channel positions and optional parent categories within a space.',
      _managementSchema(
        {
          'space_id': _managementId,
          'channels': {
            'type': 'array',
            'minItems': 1,
            'items': _managementSchema(
              {
                'id': _managementId,
                'position': {'type': 'integer', 'minimum': 0},
                'parent_id': _managementChannelFields['parent_id'],
              },
              ['id', 'position'],
            ),
          },
        },
        ['space_id', 'channels'],
      ),
      _reorderChannels,
    );
  }

  AccordAuthLoggedIn? get _managementSession {
    final state = ref.read(accordAuthProvider);
    return state is AccordAuthLoggedIn ? state : null;
  }

  bool _managementCurrent(AccordAuthLoggedIn auth) =>
      ref.mounted && ref.isCurrentAccordClient(auth.session.key, auth.client);

  Map<String, dynamic> get _managementSwitched => _managementError(
    'connection_changed',
    'Active server/account changed; retry in the intended account.',
  );

  Map<String, dynamic> _managementRestError(RestResult result) => {
    ..._restError(result),
    'code': result.error?.code.isNotEmpty == true
        ? result.error!.code
        : result.statusCode == 403
        ? 'permission_denied'
        : 'request_failed',
  };

  Future<({AccordSpace? space, Map<String, dynamic>? error})>
  _managementPermission(
    AccordAuthLoggedIn auth,
    String spaceId,
    String permission,
  ) async {
    final result = await auth.client.spaces.fetch(spaceId);
    if (!result.ok) return (space: null, error: _managementRestError(result));
    final space = result.data;
    if (space is! AccordSpace || space.id != spaceId) {
      return (
        space: null,
        error: _managementError(
          'invalid_response',
          'Server did not return the requested space.',
        ),
      );
    }
    AccordMember? member;
    var roles = space.roles;
    if (!auth.session.isAdmin && space.ownerId != auth.session.userId) {
      final memberResult = await auth.client.members.fetch(
        spaceId,
        auth.session.userId,
      );
      if (!memberResult.ok)
        return (space: null, error: _managementRestError(memberResult));
      if (memberResult.data is! AccordMember) {
        return (
          space: null,
          error: _managementError(
            'invalid_response',
            'Server did not return your membership.',
          ),
        );
      }
      member = memberResult.data as AccordMember;
      final rolesResult = await auth.client.roles.list(spaceId);
      if (!rolesResult.ok)
        return (space: null, error: _managementRestError(rolesResult));
      if (rolesResult.data is! List) {
        return (
          space: null,
          error: _managementError(
            'invalid_response',
            'Server did not return space roles.',
          ),
        );
      }
      roles = (rolesResult.data as List).whereType<AccordRole>().toList();
    }
    final permissions = accordEffectivePermissions(
      space: space,
      selfMember: member,
      roles: roles,
      currentUserId: auth.session.userId,
      currentUserIsAdmin: auth.session.isAdmin,
    );
    if (!accordHasPermission(permissions, permission)) {
      return (
        space: null,
        error: {
          ..._managementError(
            'permission_denied',
            'Missing $permission permission.',
          ),
          'permission': permission,
          'space_id': spaceId,
        },
      );
    }
    return (space: space, error: null);
  }

  Map<String, dynamic>? _managementImages(Map<String, dynamic> data) {
    for (final field in ['icon', 'banner']) {
      final value = data[field];
      if (value == null) continue;
      final match = RegExp(
        r'^data:image/(png|jpeg|gif|webp);base64,(.+)$',
      ).firstMatch(value as String);
      if (match != null) {
        try {
          if (base64Decode(match.group(2)!).isNotEmpty) continue;
        } on FormatException {
          // Return a field-specific error without echoing the image data.
        }
      }
      return _managementError(
        'validation_error',
        '$field must be a base64 image data URI or null.',
        field: field,
      );
    }
    return null;
  }

  void _cacheManagementSpace(AccordAuthLoggedIn auth, AccordSpace space) {
    if (!_managementCurrent(auth)) return;
    ref.read(spacesControllerProvider.notifier).upsertSpace(space);
    ref
        .read(connectionsControllerProvider.notifier)
        .upsertSpace(auth.session.key, space);
  }

  Future<Map<String, dynamic>> _createSpace(Map<String, dynamic> args) async {
    final error = _managementImages(args);
    if (error != null) return error;
    final auth = _managementSession;
    if (auth == null) return _notConnected;
    final result = await auth.client.spaces.create(args);
    if (!result.ok) return _managementRestError(result);
    final space = result.data;
    if (space is! AccordSpace || space.id.isEmpty) {
      return _managementError(
        'invalid_response',
        'Space creation succeeded but the server returned no space ID. Check list_spaces before retrying.',
      );
    }
    _cacheManagementSpace(auth, space);
    return {'ok': true, 'space': space.toJson()};
  }

  Future<Map<String, dynamic>> _updateSpace(Map<String, dynamic> args) async {
    final data = {...args}..remove('space_id');
    if (data.isEmpty)
      return _managementError('validation_error', 'No fields to update');
    final imageError = _managementImages(data);
    if (imageError != null) return imageError;
    final auth = _managementSession;
    if (auth == null) return _notConnected;
    final spaceId = args['space_id'] as String;
    final permission = await _managementPermission(
      auth,
      spaceId,
      AccordPermission.manageSpace,
    );
    if (permission.error != null) return permission.error!;
    for (final field in ['rules_channel_id', 'system_channel_id']) {
      if (data[field] == null) continue;
      final result = await auth.client.channels.fetch(data[field] as String);
      if (!result.ok) return _managementRestError(result);
      if (result.data is! AccordChannel ||
          (result.data as AccordChannel).spaceId != spaceId) {
        return _managementError(
          'validation_error',
          '$field must belong to this space.',
          field: field,
        );
      }
    }
    if (!_managementCurrent(auth)) return _managementSwitched;
    final result = await auth.client.spaces.update(spaceId, data);
    if (!result.ok) return _managementRestError(result);
    final space = result.data;
    if (space is! AccordSpace || space.id != spaceId) {
      return _managementError(
        'invalid_response',
        'Space updated but server returned no entity; use get_space before retrying.',
      );
    }
    if (_managementCurrent(auth)) {
      if (data.containsKey('icon') && data['icon'] == null) space.icon = null;
      if (data.containsKey('banner') && data['banner'] == null)
        space.banner = null;
      final cdnUrl = auth.session.server.cdnUrl;
      await spaceMediaCache.invalidate(
        [
          if (data.containsKey('icon')) ...[
            accordSpaceIconUrl(permission.space!, cdnUrl, versioned: false),
            accordSpaceIconUrl(space, cdnUrl, versioned: false),
          ],
          if (data.containsKey('banner')) ...[
            accordSpaceBannerUrl(permission.space!, cdnUrl, versioned: false),
            accordSpaceBannerUrl(space, cdnUrl, versioned: false),
          ],
        ].whereType<String>(),
      );
      _cacheManagementSpace(auth, space);
    }
    return {'ok': true, 'space': space.toJson()};
  }

  Future<Map<String, dynamic>?> _managementParent(
    AccordAuthLoggedIn auth,
    String spaceId,
    Map data,
    String type, {
    String? channelId,
  }) async {
    final parentId = data['parent_id'];
    if (parentId == null) return null;
    if (type == 'category' || parentId == channelId) {
      return _managementError(
        'validation_error',
        'Categories cannot be nested and channels cannot parent themselves.',
        field: 'parent_id',
      );
    }
    final result = await auth.client.channels.fetch(parentId as String);
    if (!result.ok) return _managementRestError(result);
    final parent = result.data;
    if (parent is! AccordChannel ||
        parent.spaceId != spaceId ||
        parent.type != 'category') {
      return _managementError(
        'validation_error',
        'parent_id must be a category in this space.',
        field: 'parent_id',
      );
    }
    return null;
  }

  Future<Map<String, dynamic>> _createChannel(Map<String, dynamic> args) =>
      _writeManagementChannel(args, create: true);

  Future<Map<String, dynamic>> _updateChannel(Map<String, dynamic> args) =>
      _writeManagementChannel(args, create: false);

  Future<Map<String, dynamic>> _writeManagementChannel(
    Map<String, dynamic> args, {
    required bool create,
  }) async {
    final data = {...args}
      ..remove('space_id')
      ..remove('channel_id');
    if (data.isEmpty)
      return _managementError('validation_error', 'No fields to update');
    final auth = _managementSession;
    if (auth == null) return _notConnected;
    final spaceId = args['space_id'] as String;
    final channelId = args['channel_id'] as String?;
    final permission = await _managementPermission(
      auth,
      spaceId,
      AccordPermission.manageChannels,
    );
    if (permission.error != null) return permission.error!;
    var type = data['type'] as String? ?? 'text';
    if (!create) {
      final result = await auth.client.channels.fetch(channelId!);
      if (!result.ok) return _managementRestError(result);
      final channel = result.data;
      if (channel is! AccordChannel || channel.spaceId != spaceId) {
        return _managementError(
          'validation_error',
          'channel_id must belong to this space.',
          field: 'channel_id',
        );
      }
      type = data['type'] as String? ?? channel.type;
      if (type != channel.type &&
          !({'text', 'announcement'}.contains(type) &&
              {'text', 'announcement'}.contains(channel.type))) {
        return _managementError(
          'validation_error',
          'Existing channel types can only change between text and announcement.',
          field: 'type',
        );
      }
    }
    final parentError = await _managementParent(
      auth,
      spaceId,
      data,
      type,
      channelId: channelId,
    );
    if (parentError != null) return parentError;
    if (!_managementCurrent(auth)) return _managementSwitched;
    final result = create
        ? await auth.client.spaces.createChannel(spaceId, data)
        : await auth.client.channels.update(channelId!, data);
    if (!result.ok) return _managementRestError(result);
    final channel = result.data;
    if (channel is! AccordChannel || channel.id.isEmpty) {
      return _managementError(
        'invalid_response',
        'Channel mutation succeeded but server returned no entity; use list_channels before retrying.',
      );
    }
    final warning = await _refreshManagementChannels(
      auth,
      spaceId,
      upsert: channel,
    );
    return {
      'ok': true,
      'channel': channel.toJson(),
      if (warning != null) 'warning': warning,
    };
  }

  Future<Map<String, dynamic>> _deleteChannel(Map<String, dynamic> args) async {
    final auth = _managementSession;
    if (auth == null) return _notConnected;
    final spaceId = args['space_id'] as String;
    final channelId = args['channel_id'] as String;
    final permission = await _managementPermission(
      auth,
      spaceId,
      AccordPermission.manageChannels,
    );
    if (permission.error != null) return permission.error!;
    final fetched = await auth.client.channels.fetch(channelId);
    if (!fetched.ok) return _managementRestError(fetched);
    if (fetched.data is! AccordChannel ||
        (fetched.data as AccordChannel).spaceId != spaceId) {
      return _managementError(
        'validation_error',
        'channel_id must belong to this space.',
        field: 'channel_id',
      );
    }
    if (!_managementCurrent(auth)) return _managementSwitched;
    final result = await auth.client.channels.delete(channelId);
    if (!result.ok) return _managementRestError(result);
    final warning = await _refreshManagementChannels(
      auth,
      spaceId,
      removedId: channelId,
    );
    return {
      'ok': true,
      'deleted_channel_id': channelId,
      if (warning != null) 'warning': warning,
    };
  }

  Future<Map<String, dynamic>?> _refreshManagementChannels(
    AccordAuthLoggedIn auth,
    String spaceId, {
    AccordChannel? upsert,
    String? removedId,
  }) async {
    if (!_managementCurrent(auth)) return null;
    final provider = accordChannelsControllerProvider(
      auth.session.key,
      spaceId,
    );
    // Invalidate any older pending list load before applying the REST result.
    ref.invalidate(provider);
    final controller = ref.read(provider.notifier);
    final result = await auth.client.spaces.listChannels(spaceId);
    if (!_managementCurrent(auth)) return null;
    if (result.ok && result.data is List) {
      final channels = (result.data as List)
          .whereType<AccordChannel>()
          .toList();
      controller.setChannels(channels);
    }
    if (upsert != null) controller.upsertChannel(upsert);
    if (removedId != null) controller.removeChannel(removedId);
    return !result.ok
        ? _managementRestError(result)
        : result.data is! List
        ? _managementError(
            'invalid_response',
            'Could not refresh the channel list.',
          )
        : null;
  }

  Future<Map<String, dynamic>> _reorderChannels(
    Map<String, dynamic> args,
  ) async {
    final entries = (args['channels'] as List).cast<Map>();
    if (entries.map((entry) => entry['id']).toSet().length != entries.length) {
      return _managementError(
        'validation_error',
        'Channel IDs must be unique.',
        field: 'channels',
      );
    }
    final auth = _managementSession;
    if (auth == null) return _notConnected;
    final spaceId = args['space_id'] as String;
    final permission = await _managementPermission(
      auth,
      spaceId,
      AccordPermission.manageChannels,
    );
    if (permission.error != null) return permission.error!;
    final fetched = await auth.client.spaces.listChannels(spaceId);
    if (!fetched.ok) return _managementRestError(fetched);
    if (fetched.data is! List)
      return _managementError(
        'invalid_response',
        'Server did not return channels.',
      );
    final channels = (fetched.data as List).whereType<AccordChannel>().toList();
    for (final entry in entries) {
      final channel = channels.firstWhereOrNull((c) => c.id == entry['id']);
      if (channel == null)
        return _managementError(
          'validation_error',
          'Every reordered channel must belong to this space.',
          field: 'channels',
        );
      final error = await _managementParent(
        auth,
        spaceId,
        entry,
        channel.type,
        channelId: channel.id,
      );
      if (error != null) return error;
    }
    if (!_managementCurrent(auth)) return _managementSwitched;
    final result = await auth.client.spaces.reorderChannels(spaceId, entries);
    if (!result.ok) return _managementRestError(result);
    final warning = await _refreshManagementChannels(auth, spaceId);
    final updated = _managementCurrent(auth)
        ? ref.read(accordChannelsControllerProvider(auth.session.key, spaceId))
        : null;
    return {
      'ok': true,
      'space_id': spaceId,
      if (updated != null && warning == null)
        'channels': [for (final channel in updated) channel.toJson()],
      if (warning != null) 'warning': warning,
    };
  }
}
