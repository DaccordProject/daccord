import 'package:bonfire/features/channels/controllers/muted_channels.dart';
import 'package:bonfire/features/channels/utils/toggle_channel_mute.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A rejected mute used to roll the optimistic toggle back in silence — the
/// switch sprang and nothing said why (#306). Both surfaces that toggle a mute
/// (the channel header's notification menu, the channel context menu) now go
/// through [toggleChannelMute], so these lock the reporting in one place.

/// Returns a fixed [MuteResult] instead of talking to a server, and records the
/// arguments it was called with.
class _FakeMutedChannels extends MutedChannelsController {
  _FakeMutedChannels(this._result);

  final MuteResult _result;
  final List<(String, bool)> calls = [];

  @override
  Future<Set<String>> build(String serverKey) async => const {};

  @override
  Future<MuteResult> setMuted(String channelId, bool muted) async {
    calls.add((channelId, muted));
    return _result;
  }
}

Future<_FakeMutedChannels> _tapToggle(
  WidgetTester tester,
  MuteResult result, {
  bool muted = false,
}) async {
  final fake = _FakeMutedChannels(result);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mutedChannelsControllerProvider('server').overrideWith(() => fake),
      ],
      child: MaterialApp(
        theme: buildAppTheme(AppThemePreset.dark),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => toggleChannelMute(
                context,
                ref,
                serverKey: 'server',
                channelId: 'c1',
                muted: muted,
              ),
              child: const Text('toggle'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('toggle'));
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('a rejected mute says so instead of just springing back', (
    tester,
  ) async {
    final fake = await _tapToggle(tester, MuteResult.failed);

    expect(fake.calls, [('c1', true)]);
    expect(find.text('Failed to mute channel'), findsOneWidget);
  });

  testWidgets('a rejected unmute names the direction it failed in', (
    tester,
  ) async {
    final fake = await _tapToggle(tester, MuteResult.failed, muted: true);

    expect(fake.calls, [('c1', false)]);
    expect(find.text('Failed to unmute channel'), findsOneWidget);
  });

  testWidgets('a successful mute stays quiet', (tester) async {
    await _tapToggle(tester, MuteResult.ok);

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a repeat tap while one is in flight is not an error', (
    tester,
  ) async {
    // MuteResult.busy means the earlier request still owns the outcome;
    // reporting it would be a false alarm.
    await _tapToggle(tester, MuteResult.busy);

    expect(find.byType(SnackBar), findsNothing);
  });
}
