import 'package:bonfire/features/member/views/accord_member_list.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('rosterOfflineCount', () {
    test('uses complete space metadata instead of the loaded page size', () {
      expect(
        rosterOfflineCount(
          memberCount: 237,
          presenceCount: 4,
          loadedOfflineCount: 96,
        ),
        233,
      );
    });

    test('falls back to visible rows for older servers', () {
      expect(
        rosterOfflineCount(
          memberCount: null,
          presenceCount: null,
          loadedOfflineCount: 99,
        ),
        99,
      );
    });

    test('never reports fewer members than are already loaded', () {
      expect(
        rosterOfflineCount(
          memberCount: 90,
          presenceCount: 5,
          loadedOfflineCount: 99,
        ),
        99,
      );
    });
  });
}
