import 'package:accordkit/accordkit.dart';
import 'package:test/test.dart';

void main() {
  group('AccordUser', () {
    test('parses fields and coerces int id to string', () {
      final u = AccordUser.fromJson({
        'id': 123,
        'username': 'alice',
        'display_name': 'Alice',
        'bot': true,
        'flags': 5,
        'is_admin': true,
      });
      expect(u.id, '123');
      expect(u.username, 'alice');
      expect(u.displayName, 'Alice');
      expect(u.bot, isTrue);
      expect(u.flags, 5);
      expect(u.isAdmin, isTrue);
    });

    test('toJson omits null optionals', () {
      final u = AccordUser(id: '1', username: 'bob');
      final j = u.toJson();
      expect(j['id'], '1');
      expect(j.containsKey('display_name'), isFalse);
      expect(j.containsKey('avatar'), isFalse);
      // A local user has no origin and omits it.
      expect(j.containsKey('origin'), isFalse);
    });
  });

  group('federation origin', () {
    test('user round-trips origin', () {
      final u = AccordUser.fromJson({
        'id': '123@b.example',
        'username': 'alice@b.example',
        'origin': 'b.example',
      });
      expect(u.origin, 'b.example');
      expect(u.toJson()['origin'], 'b.example');
    });

    test('member infers origin from a qualified user id', () {
      final m = AccordMember.fromJson({
        'space_id': '7@b.example',
        'user': {'id': '123@b.example', 'username': 'alice@b.example'},
      });
      expect(m.isRemote, isTrue);
      expect(m.homeDomain, 'b.example');
    });

    test('local member is not remote', () {
      final m = AccordMember.fromJson({
        'space_id': '7',
        'user': {'id': '123', 'username': 'bob'},
      });
      expect(m.isRemote, isFalse);
      expect(m.homeDomain, isNull);
      expect(m.toJson().containsKey('origin'), isFalse);
    });

    test('message infers origin from a qualified author id', () {
      final msg = AccordMessage.fromJson({
        'id': '9@b.example',
        'channel_id': '5@b.example',
        'author': {'id': '123@b.example'},
        'content': 'hi',
      });
      expect(msg.isRemote, isTrue);
      expect(msg.origin, 'b.example');
      // Dedup/ordering keys keep the full qualified author id.
      expect(msg.authorId, '123@b.example');
    });

    test('space exposes origin and isRemote', () {
      final s = AccordSpace.fromJson({
        'id': '7@b.example',
        'name': 'Remote',
        'origin': 'b.example',
      });
      expect(s.isRemote, isTrue);
      expect(s.toJson()['origin'], 'b.example');
    });
  });

  group('AccordApplication', () {
    test('reads owner.id over owner_id', () {
      final a = AccordApplication.fromJson({
        'id': '1',
        'owner': {'id': '99'},
      });
      expect(a.ownerId, '99');
    });

    test('falls back to owner_id', () {
      final a = AccordApplication.fromJson({'id': '1', 'owner_id': '42'});
      expect(a.ownerId, '42');
    });
  });

  group('AccordChannel', () {
    test('parses space_id from guild_id alias and overwrites', () {
      final c = AccordChannel.fromJson({
        'id': '1',
        'guild_id': '7',
        'rate_limit_per_user': 5,
        'permission_overwrites': [
          {'id': '3', 'type': 'member', 'allow': [], 'deny': []},
        ],
      });
      expect(c.spaceId, '7');
      expect(c.rateLimit, 5);
      expect(c.permissionOverwrites.single.type, 'user');
    });

    test('roundtrips recipients', () {
      final c = AccordChannel.fromJson({
        'id': '1',
        'type': 'group_dm',
        'recipients': [
          {'id': '2', 'username': 'x'},
        ],
      });
      expect(c.recipients!.single.username, 'x');
      final j = c.toJson();
      expect((j['recipients'] as List).single['username'], 'x');
    });
  });

  group('AccordMessage', () {
    test('parses author, mentions, attachments, embeds, reply_to', () {
      final m = AccordMessage.fromJson({
        'id': '10',
        'channel_id': '5',
        'guild_id': '7',
        'author': {'id': '2'},
        'content': 'hello',
        'mentions': [
          {'id': '3'},
          '4',
        ],
        'mention_roles': [9],
        'attachments': [
          {'id': '1', 'filename': 'a.png', 'size': 10, 'url': 'u'},
        ],
        'embeds': [
          {'title': 'T'},
        ],
        'message_reference': {'message_id': '99'},
        'reactions': [
          {'emoji': '👍', 'count': 2, 'me': true},
        ],
      });
      expect(m.spaceId, '7');
      expect(m.authorId, '2');
      expect(m.mentions, ['3', '4']);
      expect(m.mentionRoles, ['9']);
      expect(m.attachments.single.filename, 'a.png');
      expect(m.embeds.single.title, 'T');
      expect(m.replyTo, '99');
      expect(m.reactions!.single.count, 2);
      expect(m.reactions!.single.includesMe, isTrue);
    });

    test('toJson includes attachments/embeds and omits empty extras', () {
      final m = AccordMessage(id: '1', channelId: '2', content: 'hi');
      final j = m.toJson();
      expect(j['attachments'], isEmpty);
      expect(j['embeds'], isEmpty);
      expect(j.containsKey('reply_count'), isFalse);
      expect(j.containsKey('thread_participants'), isFalse);
    });
  });

  group('AccordMember', () {
    test('reads nested user and nick alias', () {
      final m = AccordMember.fromJson({
        'user': {'id': '2', 'username': 'x'},
        'guild_id': '7',
        'nick': 'Nicky',
        'roles': [1, 2],
        'communication_disabled_until': 'soon',
      });
      expect(m.userId, '2');
      expect(m.user!.username, 'x');
      expect(m.spaceId, '7');
      expect(m.nickname, 'Nicky');
      expect(m.roles, ['1', '2']);
      expect(m.timedOutUntil, 'soon');
    });
  });

  group('AccordEmbed builder', () {
    test('chains setters and serialises', () {
      final e = AccordEmbed.build()
          .setTitle('Title')
          .setDescription('Desc')
          .setColor(0xFF0000)
          .addField('k', 'v', inline: true)
          .setFooter('foot', iconUrl: 'icon')
          .setAuthor('auth');
      final j = e.toJson();
      expect(j['title'], 'Title');
      expect(j['color'], 0xFF0000);
      expect((j['fields'] as List).single['inline'], isTrue);
      expect((j['footer'] as Map)['icon_url'], 'icon');
      expect((j['author'] as Map)['name'], 'auth');
    });
  });

  group('AccordEmoji', () {
    test('null id stays null, roles aliased', () {
      final e = AccordEmoji.fromJson({
        'name': 'smile',
        'roles': [1, 2],
      });
      expect(e.id, isNull);
      expect(e.roleIds, ['1', '2']);
      expect(e.toJson().containsKey('id'), isFalse);
    });
  });

  group('AccordReaction', () {
    test('string emoji shorthand', () {
      final r = AccordReaction.fromJson({'emoji': '🔥', 'count': 1});
      expect(r.emoji['id'], isNull);
      expect(r.emoji['name'], '🔥');
    });

    test('splits custom emoji token name:id', () {
      final r = AccordReaction.fromJson(
          {'emoji': 'cube2:323038910819074048', 'count': 1});
      expect(r.emoji['id'], '323038910819074048');
      expect(r.emoji['name'], 'cube2');
    });

    test('non-numeric tail after colon stays part of the name', () {
      final r = AccordReaction.fromJson({'emoji': ':hamburger:', 'count': 1});
      expect(r.emoji['id'], isNull);
      expect(r.emoji['name'], ':hamburger:');
    });

    test('map emoji keeps explicit id and name', () {
      final r = AccordReaction.fromJson({
        'emoji': {'id': '42', 'name': 'cube2'},
        'count': 1,
      });
      expect(r.emoji['id'], '42');
      expect(r.emoji['name'], 'cube2');
    });
  });

  group('AccordSpace', () {
    test('parses roles and emojis', () {
      final s = AccordSpace.fromJson({
        'id': '1',
        'name': 'Space',
        'roles': [
          {'id': '1', 'name': 'admin'},
        ],
        'emojis': [
          {'id': '2', 'name': 'e'},
        ],
        'member_count': 3,
      });
      expect(s.roles.single.name, 'admin');
      expect(s.emojis.single.name, 'e');
      expect(s.memberCount, 3);
    });
  });

  group('AccordVoiceServerUpdate', () {
    test('aliases url/endpoint and nested voice_state', () {
      final v = AccordVoiceServerUpdate.fromJson({
        'space_id': '1',
        'channel_id': '2',
        'backend': 'livekit',
        'url': 'wss://lk',
        'endpoint': 'sfu',
        'voice_state': {'user_id': '9', 'channel_id': '2'},
      });
      expect(v.livekitUrl, 'wss://lk');
      expect(v.sfuEndpoint, 'sfu');
      expect(v.voiceState!.userId, '9');
    });
  });

  group('AccordVoiceState', () {
    test('nullable channel_id', () {
      final v = AccordVoiceState.fromJson({'user_id': '1'});
      expect(v.channelId, isNull);
      expect(v.toJson().containsKey('channel_id'), isFalse);
    });
  });

  group('AccordRelationship', () {
    test('extracts user status/activities', () {
      final r = AccordRelationship.fromJson({
        'id': '1',
        'type': 1,
        'user': {
          'id': '2',
          'username': 'x',
          'status': 'online',
          'activities': [
            {'name': 'game'},
          ],
        },
      });
      expect(r.type, 1);
      expect(r.user!.id, '2');
      expect(r.userStatus, 'online');
      expect(r.userActivities, hasLength(1));
    });
  });

  group('AccordPluginManifest', () {
    test('canvas_size array and defaults', () {
      final m = AccordPluginManifest.fromJson({
        'id': '1',
        'name': 'p',
        'canvas_size': [800, 600],
        'max_spectators': -1,
      });
      expect(m.canvasSize, [800, 600]);
      expect(m.maxSpectators, -1);
    });

    test('canvas_width/height fallback', () {
      final m = AccordPluginManifest.fromJson({
        'id': '1',
        'canvas_width': 320,
        'canvas_height': 240,
      });
      expect(m.canvasSize, [320, 240]);
    });
  });

  group('AccordInvite', () {
    test('inviter object and guild_id alias', () {
      final i = AccordInvite.fromJson({
        'code': 'abc',
        'guild_id': '7',
        'channel_id': '5',
        'inviter': {'id': '2'},
      });
      expect(i.spaceId, '7');
      expect(i.inviterId, '2');
    });
  });

  group('AccordInteraction', () {
    test('member.user.id and message', () {
      final it = AccordInteraction.fromJson({
        'id': '1',
        'application_id': '9',
        'member': {
          'user': {'id': '2'},
        },
        'message': {'id': '10', 'channel_id': '5'},
      });
      expect(it.memberId, '2');
      expect(it.message!.id, '10');
    });
  });

  group('AccordActivity', () {
    test('roundtrip', () {
      final a = AccordActivity.fromJson({'name': 'g', 'type': 'streaming'});
      expect(a.toJson()['type'], 'streaming');
    });
  });

  group('AccordAuditLogEntry / AccordCommand / AccordRole / AccordSound', () {
    test('audit log entry', () {
      final e = AccordAuditLogEntry.fromJson({
        'id': '1',
        'user_id': '2',
        'action_type': 'ban',
      });
      expect(e.toJson()['action_type'], 'ban');
    });

    test('command guild_id alias', () {
      final c = AccordCommand.fromJson({'id': '1', 'guild_id': '7'});
      expect(c.spaceId, '7');
    });

    test('role permissions list', () {
      final r = AccordRole.fromJson({
        'id': '1',
        'name': 'r',
        'permissions': ['administrator'],
      });
      expect(r.permissions, ['administrator']);
    });

    test('sound volume coercion', () {
      final s = AccordSound.fromJson({'name': 's', 'volume': 1});
      expect(s.volume, 1.0);
    });
  });
}
