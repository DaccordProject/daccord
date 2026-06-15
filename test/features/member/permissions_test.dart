import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/member/utils/permissions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('canManageSpaceSettings', () {
    test('returns false when perms is empty', () {
      expect(canManageSpaceSettings({}), isFalse);
    });

    test('returns true when manageSpace is granted', () {
      expect(
        canManageSpaceSettings({AccordPermission.manageSpace}),
        isTrue,
      );
    });

    test('returns true when manageRoles is granted', () {
      expect(
        canManageSpaceSettings({AccordPermission.manageRoles}),
        isTrue,
      );
    });

    test('returns true when viewAuditLog is granted', () {
      expect(
        canManageSpaceSettings({AccordPermission.viewAuditLog}),
        isTrue,
      );
    });

    test('returns true when administrator is granted (implies all)', () {
      expect(
        canManageSpaceSettings({AccordPermission.administrator}),
        isTrue,
      );
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
