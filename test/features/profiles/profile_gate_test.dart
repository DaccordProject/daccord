import 'dart:io';

import 'package:bonfire/features/profiles/models/device_profile.dart';
import 'package:bonfire/features/profiles/services/profile_store.dart';
import 'package:bonfire/features/profiles/utils/profile_pin_security.dart';
import 'package:bonfire/features/profiles/views/profile_gate.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

const _theme = BonfireThemeExtension(
  foreground: Colors.white,
  background: Color(0xFF1e1f22),
  dirtyWhite: Color(0xFFdcddde),
  gray: Color(0xFF949ba4),
  darkGray: Color(0xFF4e5058),
  primary: Color(0xFF5865f2),
  red: Color(0xFFed4245),
  green: Color(0xFF23a55a),
  yellow: Color(0xFFf0b232),
);

void main() {
  late Directory temp;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('profile-pin-copy-test-');
    Hive.init(temp.path);
    await ProfileStore.bootstrap(temp.path);
    ProfileStore.setPin(DeviceProfile.defaultId, '1234');
  });

  tearDown(() async {
    await Hive.close();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  testWidgets('locked profile says the PIN does not encrypt data', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData(extensions: const [_theme]),
          home: const ProfileGate(child: Text('Profile contents')),
        ),
      ),
    );

    expect(find.text(profilePinSecurityNotice), findsOneWidget);
    expect(find.text('Profile contents'), findsNothing);
  });
}
