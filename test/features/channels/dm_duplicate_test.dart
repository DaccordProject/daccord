import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/channels/controllers/dm_channels.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Duplicate 1:1 DMs (#379): the server deduplicates on an exact string match of
// participant ids, so the same account referenced as `7` from one surface and
// `7@a.example` from another used to open (and then list) two conversations.

const _base = 'https://a.example';
final _serverKey = '1@$_base';

AccordSession _session() => AccordSession(
  server: AccordServer.fromBaseUrl(_base),
  token: 'token',
  userId: '1',
  username: 'me',
);

AccordChannel _dm(
  String id,
  List<String> recipients, {
  String? lastMessageId,
}) => AccordChannel(
  id: id,
  type: 'dm',
  recipients: [for (final r in recipients) AccordUser(id: r)],
  lastMessageId: lastMessageId,
);

ProviderContainer _container({bool connected = true}) {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  if (connected) {
    container.read(connectionsControllerProvider.notifier).register(_session());
  }
  return container;
}

DmChannelsController _controller(ProviderContainer container) =>
    container.read(dmChannelsControllerProvider(_serverKey).notifier);

void main() {
  group('normalizeDmParticipantId', () {
    test('drops our own home domain so a local account has one shape', () {
      expect(
        normalizeDmParticipantId('7@a.example', homeDomain: 'a.example'),
        '7',
      );
      expect(
        normalizeDmParticipantId('  7@A.Example  ', homeDomain: 'a.example'),
        '7',
      );
      expect(normalizeDmParticipantId('7', homeDomain: 'a.example'), '7');
    });

    test('keeps a remote domain, lowercased', () {
      expect(
        normalizeDmParticipantId('7@B.Example', homeDomain: 'a.example'),
        '7@b.example',
      );
    });

    test('preserves invalid ids for server validation and an unknown home', () {
      expect(normalizeDmParticipantId('7@'), '7@');
      expect(normalizeDmParticipantId('7@b.example'), '7@b.example');
    });
  });

  group('dmCreateBody', () {
    test('a recipient qualified with our own domain stays a local DM', () {
      expect(dmCreateBody('7@a.example', homeDomain: 'a.example'), {
        'recipients': ['7'],
      });
    });

    test('a remote recipient keeps the federated field, normalized', () {
      expect(dmCreateBody('7@B.Example', homeDomain: 'a.example'), {
        'recipient_id': '7@b.example',
      });
    });
  });

  group('dmParticipantKey', () {
    test('ignores ourselves however our id is qualified', () {
      expect(
        dmParticipantKey(
          _dm('c', ['1@a.example', '7']),
          selfId: '1',
          homeDomain: 'a.example',
        ),
        '7',
      );
    });

    test('is null for groups and unresolvable channels', () {
      expect(
        dmParticipantKey(
          AccordChannel(
            id: 'g',
            type: 'group_dm',
            recipients: [AccordUser(id: '7')],
          ),
          selfId: '1',
        ),
        isNull,
      );
      expect(dmParticipantKey(AccordChannel(id: 'c', type: 'dm')), isNull);
      expect(dmParticipantKey(_dm('c', ['7', '8']), selfId: '1'), isNull);
    });
  });

  test('a listed conversation is reused instead of created again', () {
    final container = _container();
    final controller = _controller(container);
    controller.setChannels([
      _dm('dm-1', ['1', '7'], lastMessageId: 'm1'),
    ]);

    expect(controller.findDirectMessage('7@a.example')?.id, 'dm-1');
    expect(controller.findDirectMessage('7')?.id, 'dm-1');
    expect(controller.findDirectMessage('7@b.example'), isNull);
  });

  test(
    'legacy duplicates remain accessible, preferring history when opening',
    () {
      final container = _container();
      final controller = _controller(container);
      controller.setChannels([
        _dm('empty', ['1', '7@a.example']),
        _dm('history', ['1', '7'], lastMessageId: 'm1'),
      ]);
      controller.upsert(_dm('other-history', ['1', '7'], lastMessageId: 'm2'));
      expect(
        container.read(dmChannelsControllerProvider(_serverKey))?.length,
        3,
      );
      expect(controller.findDirectMessage('7')?.lastMessageId, isNotNull);
    },
  );

  test(
    'remote domain case matches but different domains and local parts do not',
    () {
      final controller = _controller(_container());
      controller.setChannels([
        _dm('remote', ['1', 'User@B.Example']),
      ]);
      expect(controller.findDirectMessage('  User@b.example  ')?.id, 'remote');
      expect(controller.findDirectMessage('User@c.example'), isNull);
      expect(controller.findDirectMessage('User'), isNull);
      expect(controller.findDirectMessage('user@b.example'), isNull);
    },
  );

  test('unloaded cache and group-only matches require creation', () {
    final controller = _controller(_container());
    expect(controller.findDirectMessage('7'), isNull);
    controller.setChannels([
      AccordChannel(
        id: 'group',
        type: 'group_dm',
        recipients: [AccordUser(id: '7')],
      ),
    ]);
    expect(controller.findDirectMessage('7'), isNull);
  });

  test('group DMs and unrelated accounts still list separately', () {
    final container = _container();
    final controller = _controller(container);
    controller.setChannels([
      _dm('dm-1', ['1', '7']),
      AccordChannel(
        id: 'group',
        type: 'group_dm',
        recipients: [
          AccordUser(id: '1'),
          AccordUser(id: '7'),
        ],
      ),
    ]);
    controller.upsert(_dm('dm-2', ['1', '8']));

    expect(
      container
          .read(dmChannelsControllerProvider(_serverKey))
          ?.map((channel) => channel.id),
      ['dm-2', 'dm-1', 'group'],
    );
  });

  test('without a registered connection nothing is collapsed', () {
    final container = _container(connected: false);
    final controller = _controller(container);
    controller.setChannels([
      _dm('dm-1', ['1', '7']),
      _dm('dm-2', ['1', '7@a.example']),
    ]);

    expect(container.read(dmChannelsControllerProvider(_serverKey))?.length, 2);
  });
}
