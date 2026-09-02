// A throwaway entry point that boots the real app against the seeded, offline
// fixture in `seeded_space.dart` and parks it on one screen, so a headless
// browser can photograph it for the App Store tablet screenshots.
//
// Run it through `store-media/ios-generator/capture-inner.sh`, which serves this
// entry point and drives a headless Chromium over it. Do not point it at a
// server: the transport is an in-memory `MockClient` and no socket is opened.
//
// Why a web entry point rather than a widget test: `flutter test` starts the
// engine with `--use-test-fonts`, which resolves every *unstyled* `TextStyle`
// to a box-drawing font. Message bodies are unstyled — on a device they take
// the platform's font, because `markdown_viewer`'s renderer names no family —
// so a widget test can only ever photograph message text as boxes. A browser
// supplies a real default font, and being a real engine it also renders the
// shadows, image decoding and layout the shipped app does.
//
// Scene is chosen by query string: `?scene=1` … `?scene=6`.

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/authentication/utils/hive.dart';
import 'package:bonfire/features/authentication/views/welcome_view.dart';
import 'package:bonfire/features/channels/controllers/open_tabs.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/channels/models/open_tab.dart';
import 'package:bonfire/features/events/controllers/connection.dart';
import 'package:bonfire/features/developer/services/mcp_home_bridge.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/member/views/accord_member_popout.dart';
import 'package:bonfire/features/profiles/services/profile_store.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/views/accord_home.dart';
import 'package:bonfire/features/spaces/views/accord_role_management.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/services/voice_session.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'seeded_space.dart';

/// A wider channel list than the 220pt default.
///
/// At the default an owner's five channel-list header actions leave the space
/// name no room, which reads as a broken header. The width is a user
/// preference the divider drags, so this is the app configured, not patched.
const _channelListWidth = 380.0;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupHive();
  await ProfileStore.settingsBox.put(
    'settings',
    const AccordSettings(channelListWidth: _channelListWidth).toJson(),
  );
  // Hive persists to browser storage, so without this every scene inherits the
  // tabs the previous one opened and the strip grows across a capture run.
  await ProfileStore.settingsBox.delete('open-tabs');

  final scene = int.tryParse(Uri.base.queryParameters['scene'] ?? '1') ?? 1;
  final server = AccordServer.fromBaseUrl('https://vale.example');
  final client = AccordClient(
    token: 'capture-token',
    tokenType: 'Bearer',
    baseUrl: server.baseUrl,
    gatewayUrl: server.gatewayUrl,
    cdnUrl: server.cdnUrl,
    httpClient: buildSeededTransport(),
  );
  final session = AccordSession(
    server: server,
    token: 'capture-token',
    userId: seedSelfId,
    username: seedSelfName,
  );

  final container = ProviderContainer(
    overrides: [
      accordAuthProvider.overrideWithValue(
        AccordAuthLoggedIn(client: client, session: session),
      ),
      if (scene == 2) voiceControllerProvider.overrideWith(_ConnectedVoice.new),
    ],
  );
  _seed(container, session, scene);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: _CaptureApp(scene: scene),
    ),
  );
}

/// Fills every cache the gateway would normally fill on READY.
void _seed(ProviderContainer container, AccordSession session, int scene) {
  final key = session.key;
  final spaces = [for (final s in seedSpaces) AccordSpace.fromJson(s)];

  container.read(connectionsControllerProvider.notifier)
    ..register(session, status: ConnectionStatus.connected)
    ..setSpaces(key, spaces, authoritative: true)
    ..setActive(key);
  container.read(spacesControllerProvider.notifier).setSpaces(spaces);

  // Presence is per user, not per space, and the two rosters overlap — so
  // dedupe rather than letting the second list restate the first's members.
  final presences = <String, AccordPresence>{};
  for (final m in [...seedValeMembers, ...seedTideMembers]) {
    if (m.status == 'offline') continue;
    presences.putIfAbsent(
      m.id,
      () => AccordPresence(userId: m.id, status: m.status),
    );
  }
  container
      .read(presenceControllerProvider(key).notifier)
      .seed(presences.values);

  container
      .read(voiceStatesControllerProvider(key).notifier)
      .seedChannel(seedVoiceChannelId, [
        for (final entry in seedVoiceParticipants.entries)
          AccordVoiceState(
            userId: entry.key,
            spaceId: seedSpaceId,
            channelId: seedVoiceChannelId,
            selfMute: entry.value['self_mute'] ?? false,
            selfVideo: entry.value['self_video'] ?? false,
          ),
      ]);

  container.read(readStateControllerProvider(key).notifier)
    ..markUnread('c-introductions', spaceId: seedSpaceId, isMention: true)
    ..markUnread('c-introductions', spaceId: seedSpaceId, isMention: true)
    ..markUnread('c-build-log', spaceId: seedSpaceId);

  // Scenes that are "the same screen, somewhere else" open the tab the user
  // would have tapped, rather than faking a different widget tree. The last one
  // opened is the active one.
  final tabs = container.read(openTabsControllerProvider.notifier);
  final general = OpenTab(
    channelId: seedGeneralChannelId,
    spaceId: seedSpaceId,
    serverKey: key,
    name: 'general',
  );
  tabs.open(general);
  switch (scene) {
    case 2:
      tabs.open(
        OpenTab(
          channelId: seedVoiceChannelId,
          spaceId: seedSpaceId,
          serverKey: key,
          name: 'Workbench',
        ),
      );
    case 3:
      tabs.open(
        OpenTab(
          channelId: 't-lobby',
          spaceId: seedSecondSpaceId,
          serverKey: key,
          name: 'lobby',
        ),
      );
  }
}

/// A live call with no LiveKit session behind it.
///
/// The in-call grid builds one tile per entry in the voice-state cache and
/// falls back to the avatar tile whenever a participant has no video track —
/// which is the state a camera-off call is genuinely in. Nothing here invents a
/// media track.
///
/// It reports *joining*, not "already in the call": `VoiceChannelView` decides
/// whether to keep the channel's chat beside the call from the connection state
/// it sees when it mounts, exactly as it would for a user who opened the
/// channel and then pressed Join. Starting connected would photograph the call
/// with the chat panel closed.
class _ConnectedVoice extends VoiceController {
  static const _connected = VoiceConnection(
    channelId: seedVoiceChannelId,
    spaceId: seedSpaceId,
    sessionState: VoiceSessionState.connected,
    speakingUserIds: {'u-june'},
  );

  @override
  VoiceConnection build() {
    Future<void>.delayed(
      const Duration(milliseconds: 600),
      () => state = _connected,
    );
    return const VoiceConnection();
  }
}

/// Taps the on-screen [Text] reading [label], the way the user would.
///
/// Scenes that need a selection inside a dialog cannot reach its private state,
/// and hard-coded tap coordinates rot the moment a layout changes. Walking the
/// element tree for the label and hit-testing its centre survives both.
void _tapLabel(String label) {
  Element? target;
  void visit(Element element) {
    if (target != null) return;
    final widget = element.widget;
    if (widget is Text && widget.data == label) {
      target = element;
      return;
    }
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  final box = target?.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return;
  final at = box.localToGlobal(box.size.center(Offset.zero));
  const pointer = 7;
  GestureBinding.instance
    ..handlePointerEvent(PointerDownEvent(pointer: pointer, position: at))
    ..handlePointerEvent(PointerUpEvent(pointer: pointer, position: at));
}

class _CaptureApp extends StatelessWidget {
  const _CaptureApp({required this.scene});

  final int scene;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(AppThemePreset.dark),
      // Mirrors the router shell in `lib/router/controller.dart`, which is the
      // Material ancestor every screen is really built under.
      home: Builder(
        builder: (context) => Scaffold(
          backgroundColor: BonfireThemeExtension.of(context).background,
          body: scene == 6 ? const _Welcome() : _Home(scene: scene),
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: ConstrainedBox(
        // The same 760pt column `AccordLoginScreen._centered` gives it.
        constraints: const BoxConstraints(maxWidth: 760),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: WelcomeView(onBrowse: _noop, onManualConnect: _noop),
        ),
      ),
    ),
  );
}

void _noop() {}

/// The home screen, with the overlay scenes 4 and 5 opened once it has settled.
class _Home extends StatefulWidget {
  const _Home({required this.scene});

  final int scene;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  @override
  void initState() {
    super.initState();
    if (widget.scene == 2) {
      // The call scene shows the video grid beside the channel's own chat, and
      // `VoiceChannelView` only splits them above 720pt of message column. Fold
      // the roster away through the home screen's own toggle — the same action
      // the Members button performs — rather than shrinking a pane.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        mcpHomeBridge.invoke('toggle_member_list', const {});
      });
      return;
    }
    if (widget.scene != 4 && widget.scene != 5) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Let the seeded REST reads land so the dialog opens over a populated
      // screen rather than a spinner.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      if (widget.scene == 4) {
        await showAccordMemberPopout(
          context,
          spaceId: seedSpaceId,
          userId: 'u-hana',
        );
      } else {
        // Select a role once the dialog is up: its right-hand pane is a "Select
        // a role to edit" placeholder until one is, which is not what the
        // permission editor looks like in use.
        Future<void>.delayed(
          const Duration(milliseconds: 900),
          () => _tapLabel('Moderators'),
        );
        await showAccordRoleManagement(context, spaceId: seedSpaceId);
      }
    });
  }

  @override
  Widget build(BuildContext context) => const AccordHomeScreen();
}
