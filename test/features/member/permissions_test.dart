import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/member/utils/permissions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('accordEffectivePermissions', () {
    final roles = [
      AccordRole(
        id: 'everyone',
        position: 0,
        permissions: [AccordPermission.sendMessages],
      ),
      AccordRole(
        id: 'moderator',
        position: 5,
        permissions: [AccordPermission.manageMessages],
      ),
    ];

    test('grants instance administrators the administrator bypass', () {
      final permissions = accordEffectivePermissions(
        space: AccordSpace(id: 'space'),
        selfMember: AccordMember(userId: 'self'),
        roles: roles,
        currentUserId: 'self',
        currentUserIsAdmin: true,
      );

      expect(permissions, {AccordPermission.administrator});
    });

    test('role preview suppresses the instance-administrator bypass', () {
      final permissions = accordEffectivePermissions(
        space: AccordSpace(id: 'space'),
        selfMember: AccordMember(userId: 'self'),
        roles: roles,
        currentUserId: 'self',
        currentUserIsAdmin: true,
        previewRoleId: 'moderator',
      );

      expect(permissions, {
        AccordPermission.sendMessages,
        AccordPermission.manageMessages,
      });
    });
  });

  group('canManageSpaceSettings', () {
    test('returns false when perms is empty', () {
      expect(canManageSpaceSettings({}), isFalse);
    });

    test('returns true when manageSpace is granted', () {
      expect(canManageSpaceSettings({AccordPermission.manageSpace}), isTrue);
    });

    test('returns true when manageRoles is granted', () {
      expect(canManageSpaceSettings({AccordPermission.manageRoles}), isTrue);
    });

    test('returns true when viewAuditLog is granted', () {
      expect(canManageSpaceSettings({AccordPermission.viewAuditLog}), isTrue);
    });

    test('returns true when administrator is granted (implies all)', () {
      expect(canManageSpaceSettings({AccordPermission.administrator}), isTrue);
    });

    test('returns false when only unrelated permissions are present', () {
      expect(
        canManageSpaceSettings({
          AccordPermission.sendMessages,
          AccordPermission.createInvites,
        }),
        isFalse,
      );
    });
  });
}
