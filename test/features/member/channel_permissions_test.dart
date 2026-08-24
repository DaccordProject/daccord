import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/member/utils/permissions.dart';
import 'package:flutter_test/flutter_test.dart';

AccordPermissionOverwrite _overwrite(
  String id, {
  String type = 'role',
  List<String> allow = const [],
  List<String> deny = const [],
}) => AccordPermissionOverwrite(id: id, type: type, allow: allow, deny: deny);

void main() {
  test('channel overwrites apply everyone, roles, then member', () {
    final channel = AccordChannel(
      permissionOverwrites: [
        _overwrite('everyone', deny: [AccordPermission.mentionEveryone]),
        _overwrite('announcer', allow: [AccordPermission.mentionEveryone]),
        _overwrite(
          'self',
          type: 'user',
          deny: [AccordPermission.mentionEveryone],
        ),
      ],
    );

    final permissions = accordEffectiveChannelPermissions(
      permissions: {AccordPermission.mentionEveryone},
      channel: channel,
      everyoneRoleId: 'everyone',
      memberRoleIds: {'announcer'},
      currentUserId: 'self',
    );

    expect(permissions, isNot(contains(AccordPermission.mentionEveryone)));
  });

  test('combined role allows win over combined role denies', () {
    final permissions = accordEffectiveChannelPermissions(
      permissions: const {},
      channel: AccordChannel(
        permissionOverwrites: [
          _overwrite('denier', deny: [AccordPermission.mentionEveryone]),
          _overwrite('announcer', allow: [AccordPermission.mentionEveryone]),
        ],
      ),
      everyoneRoleId: 'everyone',
      memberRoleIds: {'denier', 'announcer'},
      currentUserId: 'self',
    );

    expect(permissions, contains(AccordPermission.mentionEveryone));
  });

  test('administrator bypass ignores channel denies', () {
    final permissions = accordEffectiveChannelPermissions(
      permissions: {AccordPermission.administrator},
      channel: AccordChannel(
        permissionOverwrites: [
          _overwrite('everyone', deny: [AccordPermission.mentionEveryone]),
          _overwrite(
            'self',
            type: 'user',
            deny: [AccordPermission.mentionEveryone],
          ),
        ],
      ),
      everyoneRoleId: 'everyone',
      memberRoleIds: const {},
      currentUserId: 'self',
    );

    expect(
      accordHasPermission(permissions, AccordPermission.mentionEveryone),
      isTrue,
    );
  });
}
