// Curated, entirely fictional content for the App Store capture harness.
//
// Everything here is invented for the screenshots: an offline stand-in for an
// Accord server, served to the real `AccordClient` through a `MockClient`
// transport so the app's own widgets render it. Nothing is fetched, nothing is
// posted, and no live instance is contacted — see
// `docs/app-store-deploy.md` (guideline 2.3.10) for why the seeding is done
// this way rather than by photographing a real community.
//
// Two content rules apply to every string below, both enforced by
// `test/store_capture/seeded_content_test.dart`:
//
//  1. No third-party platform, product or company name may appear anywhere —
//     that is the 2.3.10 rejection we already took once.
//  2. Nothing may describe the app's own distribution, review or store status.
//
// The people, spaces and conversations are a plausible maker-community, chosen
// so a reviewer sees what the app actually does with ordinary content.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The signed-in account the captures are taken from.
const seedSelfId = 'u-mira';
const seedSelfName = 'mira';

/// The space the messaging / members / roles scenes use.
const seedSpaceId = 's-vale';

/// The second space, used for the multi-server scene.
const seedSecondSpaceId = 's-tide';

const seedGeneralChannelId = 'c-general';
const seedVoiceChannelId = 'v-workbench';

/// Every space in the rail. Only the first two are navigable; the rest exist so
/// the rail reads as the multi-server surface it is.
final List<Map<String, dynamic>> seedSpaces = [
  {
    'id': seedSpaceId,
    'name': 'Vale Makers',
    'owner_id': seedSelfId,
    'member_count': 128,
    'roles': _valeRoles,
  },
  {
    'id': seedSecondSpaceId,
    'name': 'Tidepool Arcade',
    'owner_id': 'u-tobi',
    'member_count': 74,
    'roles': _tideRoles,
  },
  {'id': 's-north', 'name': 'Northlight Studio', 'owner_id': 'u-hana'},
  {'id': 's-kite', 'name': 'Kite and Compass', 'owner_id': 'u-june'},
  {'id': 's-fox', 'name': 'Foxglove Coffee', 'owner_id': 'u-nadia'},
  {'id': 's-fern', 'name': 'Fernwood Garden', 'owner_id': 'u-omar'},
];

const _valeRoles = <Map<String, dynamic>>[
  {
    'id': 'r-everyone',
    'name': '@everyone',
    'position': 0,
    'permissions': [
      'view_channel',
      'send_messages',
      'read_history',
      'add_reactions',
    ],
  },
  {
    'id': 'r-maker',
    'name': 'Makers',
    'position': 1,
    'color': 0x7C8CFF,
    'hoist': false,
    'mentionable': true,
    'permissions': [
      'view_channel',
      'send_messages',
      'read_history',
      'add_reactions',
      'create_invites',
    ],
  },
  {
    'id': 'r-mod',
    'name': 'Moderators',
    'position': 2,
    'color': 0x46DD8A,
    'hoist': true,
    'mentionable': true,
    'permissions': [
      'view_channel',
      'send_messages',
      'read_history',
      'add_reactions',
      'create_invites',
      'manage_messages',
      'manage_channels',
      'kick_members',
      'mute_members',
    ],
  },
  {
    'id': 'r-owner',
    'name': 'Owner',
    'position': 3,
    'color': 0xE05B78,
    'hoist': true,
    'permissions': ['administrator'],
  },
];

const _tideRoles = <Map<String, dynamic>>[
  {
    'id': 'tr-everyone',
    'name': '@everyone',
    'position': 0,
    'permissions': [
      'view_channel',
      'send_messages',
      'read_history',
      'add_reactions',
    ],
  },
  {
    'id': 'tr-host',
    'name': 'Hosts',
    'position': 2,
    'color': 0xF0B429,
    'hoist': true,
    'permissions': [
      'view_channel',
      'send_messages',
      'read_history',
      'add_reactions',
      'manage_messages',
    ],
  },
];

/// `#general` first, so the space's default channel is the messaging scene's.
final List<Map<String, dynamic>> seedValeChannels = [
  _text(
    'c-general',
    'general',
    'cat-text',
    1,
    topic: 'Anything and everything',
  ),
  _text('c-introductions', 'introductions', 'cat-text', 2),
  _text('c-show-and-tell', 'show-and-tell', 'cat-text', 3),
  _text('c-off-topic', 'off-topic', 'cat-text', 4),
  _text('c-build-log', 'build-log', 'cat-workshop', 6),
  _text('c-parts-swap', 'parts-swap', 'cat-workshop', 7),
  _category('cat-text', 'Text Channels', 0),
  _category('cat-workshop', 'Workshop', 5),
  _category('cat-voice', 'Voice Channels', 8),
  _voice(seedVoiceChannelId, 'Workbench', 'cat-voice', 9),
  _voice('v-quiet', 'Quiet Room', 'cat-voice', 10),
];

final List<Map<String, dynamic>> seedTideChannels = [
  _text('t-lobby', 'lobby', 't-cat-text', 1, topic: 'Say hello'),
  _text('t-high-scores', 'high-scores', 't-cat-text', 2),
  _text('t-repairs', 'repairs', 't-cat-text', 3),
  _text('t-cabinets', 'cabinet-log', 't-cat-text', 4),
  _text('t-tournaments', 'tournaments', 't-cat-meet', 6),
  _text('t-trade-post', 'trade-post', 't-cat-meet', 7),
  _text('t-events', 'events', 't-cat-meet', 8),
  _category('t-cat-text', 'The Arcade', 0),
  _category('t-cat-meet', 'Meetups', 5),
  _category('t-cat-voice', 'Voice Channels', 9),
  _voice('t-v-couch', 'Couch Co-op', 't-cat-voice', 10),
  _voice('t-v-table', 'Tournament Table', 't-cat-voice', 11),
];

Map<String, dynamic> _text(
  String id,
  String name,
  String parent,
  int position, {
  String? topic,
}) => {
  'id': id,
  'type': 'text',
  'name': name,
  'parent_id': parent,
  'position': position,
  if (topic != null) 'topic': topic,
};

Map<String, dynamic> _voice(
  String id,
  String name,
  String parent,
  int position,
) => {
  'id': id,
  'type': 'voice',
  'name': name,
  'parent_id': parent,
  'position': position,
};

Map<String, dynamic> _category(String id, String name, int position) => {
  'id': id,
  'type': 'category',
  'name': name,
  'position': position,
};

/// One roster entry: id, display name, role ids and presence.
class SeedMember {
  const SeedMember(
    this.id,
    this.username,
    this.displayName,
    this.roles,
    this.status,
  );

  final String id;
  final String username;
  final String displayName;
  final List<String> roles;

  /// `online` / `idle` / `dnd` / `offline`.
  final String status;
}

const seedValeMembers = <SeedMember>[
  SeedMember(seedSelfId, seedSelfName, 'Mira Vale', ['r-owner'], 'online'),
  SeedMember('u-tobi', 'tobi', 'Tobi Ng', ['r-mod', 'r-maker'], 'online'),
  SeedMember('u-hana', 'hana', 'Hana Ito', ['r-mod', 'r-maker'], 'online'),
  SeedMember('u-ravi', 'ravi', 'Ravi Deo', ['r-mod'], 'idle'),
  SeedMember('u-june', 'june', 'June Park', ['r-maker'], 'online'),
  SeedMember('u-elias', 'elias', 'Elias Roth', ['r-maker'], 'online'),
  SeedMember('u-nadia', 'nadia', 'Nadia Kerr', ['r-maker'], 'online'),
  SeedMember('u-omar', 'omar', 'Omar Haddad', ['r-maker'], 'online'),
  SeedMember('u-lin', 'lin', 'Lin Zhao', ['r-maker'], 'online'),
  SeedMember('u-petra', 'petra', 'Petra Vos', ['r-maker'], 'dnd'),
  SeedMember('u-sam', 'sam', 'Sam Okafor', ['r-maker'], 'online'),
  SeedMember('u-yuki', 'yuki', 'Yuki Mori', ['r-maker'], 'online'),
  SeedMember('u-bea', 'bea', 'Bea Lindqvist', ['r-maker'], 'idle'),
  SeedMember('u-caleb', 'caleb', 'Caleb Frost', [], 'offline'),
  SeedMember('u-noor', 'noor', 'Noor Rahman', [], 'offline'),
];

const seedTideMembers = <SeedMember>[
  SeedMember(seedSelfId, seedSelfName, 'Mira Vale', [], 'online'),
  SeedMember('u-tobi', 'tobi', 'Tobi Ng', ['tr-host'], 'online'),
  SeedMember('u-june', 'june', 'June Park', ['tr-host'], 'online'),
  SeedMember('u-ravi', 'ravi', 'Ravi Deo', ['tr-host'], 'online'),
  SeedMember('u-lin', 'lin', 'Lin Zhao', [], 'online'),
  SeedMember('u-sam', 'sam', 'Sam Okafor', [], 'online'),
  SeedMember('u-elias', 'elias', 'Elias Roth', [], 'online'),
  SeedMember('u-nadia', 'nadia', 'Nadia Kerr', [], 'online'),
  SeedMember('u-yuki', 'yuki', 'Yuki Mori', [], 'online'),
  SeedMember('u-omar', 'omar', 'Omar Haddad', [], 'online'),
  SeedMember('u-petra', 'petra', 'Petra Vos', [], 'idle'),
  SeedMember('u-hana', 'hana', 'Hana Ito', [], 'idle'),
  SeedMember('u-bea', 'bea', 'Bea Lindqvist', [], 'offline'),
  SeedMember('u-caleb', 'caleb', 'Caleb Frost', [], 'offline'),
];

/// Who is sitting in `Workbench` for the voice scene, and how.
const seedVoiceParticipants = <String, Map<String, bool>>{
  seedSelfId: {'self_mute': false, 'self_video': false},
  'u-june': {'self_mute': false, 'self_video': false},
  'u-omar': {'self_mute': true, 'self_video': false},
  'u-hana': {'self_mute': false, 'self_video': false},
};

/// `#general`, oldest last (the API returns newest-first).
///
/// One reply, one mention, two reacted messages — the shapes a message pane has
/// to prove it renders.
final List<Map<String, dynamic>> seedGeneralMessages = _messages([
  _M(
    'm1',
    'u-hana',
    '09:41',
    "morning! the new lathe guards turned up, they're on the shelf by the door",
  ),
  _M(
    'm2',
    'u-june',
    '09:44',
    "oh good. i'll fit them before Thursday's open night",
  ),
  _M(
    'm3',
    'u-tobi',
    '09:52',
    'reminder that open night is Thursday at 7 — bring something '
        'half-finished, that is rather the point',
    reactions: [('🔧', 6, false), ('🎉', 4, true)],
  ),
  _M(
    'm4',
    'u-omar',
    '10:03',
    'the little rover chassis is finally printing clean at 0.2mm',
    reactions: [('✨', 5, false)],
  ),
  _M(
    'm5',
    'u-nadia',
    '10:07',
    'that is the one you fought with all last week, right? looks great',
    replyTo: 'm4',
  ),
  _M(
    'm6',
    'u-yuki',
    '10:12',
    '@mira do we still have the spare belt for the Y axis? '
        'it is not in the parts bin',
    mentions: [seedSelfId],
  ),
  _M(
    'm7',
    seedSelfId,
    '10:14',
    'yes — bottom drawer, taped to the inside of the lid. '
        'i will move it somewhere sane',
  ),
  _M(
    'm8',
    'u-elias',
    '10:18',
    'i will print a label for it. we lose that belt about once a month',
    reactions: [('😄', 3, false)],
  ),
]);

final List<Map<String, dynamic>> seedTideMessages = _messages([
  _M(
    'tm1',
    'u-june',
    '17:48',
    'cabinet number four is back from the shop — the monitor is finally '
        'not green any more',
  ),
  _M(
    'tm2',
    'u-tobi',
    '17:52',
    'heroic. did the coin door get sorted too?',
    replyTo: 'tm1',
  ),
  _M(
    'tm3',
    'u-june',
    '17:54',
    'new microswitch, yes. free play stays on though',
    reactions: [('🕹️', 7, true)],
  ),
  _M(
    'tm4',
    'u-lin',
    '18:05',
    'the high score board is updated — someone please beat my terrible '
        'pinball run',
  ),
  _M(
    'tm5',
    'u-sam',
    '18:11',
    'i can bring the spare marquee light on Saturday if anyone is around',
  ),
  _M(
    'tm6',
    'u-nadia',
    '18:14',
    'i will be there from noon, happy to help fit it',
    reactions: [('👍', 5, false)],
  ),
  _M(
    'tm7',
    'u-ravi',
    '18:19',
    'reminder that the doubles ladder starts next week — sign-ups are pinned '
        'in #tournaments',
  ),
  _M(
    'tm8',
    'u-yuki',
    '18:26',
    'signed up. bringing snacks, which is arguably my strongest event',
    reactions: [('😄', 6, true)],
  ),
], channelId: 't-lobby');

/// The `Workbench` voice channel's own text chat, shown beside the call.
final List<Map<String, dynamic>> seedVoiceChatMessages = _messages([
  _M(
    'vm1',
    'u-june',
    '19:31',
    'can everyone hear the lathe in the background?',
  ),
  _M('vm2', 'u-hana', '19:31', 'not at all, you sound fine'),
  _M(
    'vm3',
    'u-omar',
    '19:33',
    'muting for a minute, the extractor fan is on',
    reactions: [('👍', 3, false)],
  ),
  _M(
    'vm4',
    seedSelfId,
    '19:35',
    'i will share the drawing in a second so we can look at it together',
  ),
  _M(
    'vm5',
    'u-june',
    '19:36',
    'perfect. the joint on the left is the tricky one',
  ),
], channelId: seedVoiceChannelId);

class _M {
  const _M(
    this.id,
    this.author,
    this.time,
    this.content, {
    this.replyTo,
    this.mentions = const [],
    this.reactions = const [],
  });

  final String id;
  final String author;
  final String time;
  final String content;
  final String? replyTo;
  final List<String> mentions;
  final List<(String, int, bool)> reactions;
}

/// A fixed, timezone-free date so a capture run is reproducible.
const _day = '2026-05-14';

List<Map<String, dynamic>> _messages(
  List<_M> items, {
  String channelId = seedGeneralChannelId,
}) => [
  for (final m in items.reversed)
    {
      'id': m.id,
      'channel_id': channelId,
      'author_id': m.author,
      'content': m.content,
      'timestamp': '${_day}T${m.time}:00Z',
      if (m.replyTo != null) 'reply_to': m.replyTo,
      if (m.mentions.isNotEmpty) 'mentions': m.mentions,
      if (m.reactions.isNotEmpty)
        'reactions': [
          for (final (emoji, count, me) in m.reactions)
            {
              'emoji': {'id': null, 'name': emoji},
              'count': count,
              'me': me,
            },
        ],
    },
];

Map<String, dynamic> _memberJson(SeedMember m, String spaceId) => {
  'space_id': spaceId,
  'joined_at': '2025-11-02T09:00:00Z',
  'roles': m.roles,
  'user': {
    'id': m.id,
    'username': m.username,
    'display_name': m.displayName,
    if (m.id == 'u-tobi') 'bio': 'Keeps the workshop tidy. Mostly.',
  },
};

/// A `MockClient` standing in for the whole Accord REST surface.
///
/// Anything not seeded answers with an empty list, which is what every consumer
/// treats as "nothing here" — so an endpoint added later degrades to an empty
/// pane rather than an exception in the capture.
MockClient buildSeededTransport() {
  return MockClient((request) async {
    final path = request.url.path;
    List<dynamic>? list;

    if (path.endsWith('/spaces/$seedSpaceId/channels')) {
      list = seedValeChannels;
    } else if (path.endsWith('/spaces/$seedSecondSpaceId/channels')) {
      list = seedTideChannels;
    } else if (path.endsWith('/spaces/$seedSpaceId/members')) {
      list = [for (final m in seedValeMembers) _memberJson(m, seedSpaceId)];
    } else if (path.endsWith('/spaces/$seedSecondSpaceId/members')) {
      list = [
        for (final m in seedTideMembers) _memberJson(m, seedSecondSpaceId),
      ];
    } else if (path.endsWith('/channels/$seedGeneralChannelId/messages')) {
      list = seedGeneralMessages;
    } else if (path.endsWith('/channels/t-lobby/messages')) {
      list = seedTideMessages;
    } else if (path.endsWith('/channels/$seedVoiceChannelId/messages')) {
      list = seedVoiceChatMessages;
    } else if (path.endsWith('/settings')) {
      return _json({'data': <String, dynamic>{}});
    }

    return _json(list ?? const []);
  });
}

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);
