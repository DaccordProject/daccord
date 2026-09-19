import 'dart:async';
import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/events/services/accord_event_handler.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/messaging/controllers/forum_posts.dart';
import 'package:bonfire/features/messaging/controllers/thread_replies.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _channel = 'channel';
const _key = 'self@https://accord.example.test';

enum _Kind { messages, replies, posts }

final _refProvider = Provider<Ref>((ref) => ref);

class _QuietSettings extends SettingsController {
  @override
  AccordSettings build() =>
      const AccordSettings(notificationsEnabled: false, soundsEnabled: false);
}

class _Gateway implements GatewayConnection {
  final _frames = StreamController<String>();
  void event(String type, Map<String, dynamic> data) => _frames.add(
    jsonEncode({'op': GatewayOpcodes.event, 'type': type, 'data': data}),
  );
  @override
  Future<void> get ready => Future.value();
  @override
  Stream<String> get messages => _frames.stream;
  @override
  void sendText(String text) {}
  @override
  Future<void> close([int? code, String? reason]) => _frames.close();
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
}

AccordMessage _message(String id, [String? content]) =>
    AccordMessage(id: id, channelId: _channel, content: content ?? id);

List<AccordMessage> _page(String prefix) => [
  for (var i = 50; i > 0; i--) _message('$prefix$i'),
];

class _Pending {
  _Pending(this.request);
  final http.Request request;
  final response = Completer<http.Response>();

  void complete(List<AccordMessage> messages) => response.complete(
    http.Response(jsonEncode(messages.map((m) => m.toJson()).toList()), 200),
  );
  void fail() => response.complete(http.Response('{}', 403));
}

class _Account {
  _Account({String user = 'self', String host = 'accord.example.test'}) {
    final server = AccordServer.fromBaseUrl('https://$host');
    client = AccordClient(
      token: user,
      connectionFactory: (_) => gateway,
      baseUrl: server.baseUrl,
      gatewayUrl: server.gatewayUrl,
      cdnUrl: server.cdnUrl,
      httpClient: MockClient((request) {
        if (request.url.path.endsWith('/users/@me/spaces')) {
          final pending = _Pending(request);
          spaces.add(pending);
          return pending.response.future;
        }
        final reactorPath = RegExp(
          r'/messages/([^/]+)/reactions/([^/]+)$',
        ).firstMatch(request.url.path);
        if (reactorPath != null) {
          final key =
              '${reactorPath[1]}/${Uri.decodeComponent(reactorPath[2]!)}';
          reactorRequests.add(key);
          return (heldReactors[key]?.future ?? Future.value()).then(
            (_) => http.Response(
              jsonEncode([
                for (final id in reactors[key] ?? const <String>[])
                  {'id': id, 'username': id},
              ]),
              200,
            ),
          );
        }
        if (!request.url.path.endsWith('/messages')) {
          return Future.value(http.Response('[]', 200));
        }
        final pending = _Pending(request);
        _requests.add(pending);
        return pending.response.future;
      }),
    );
    auth = AccordAuthLoggedIn(
      client: client,
      session: AccordSession(
        server: server,
        token: user,
        userId: user,
        username: user,
      ),
    );
    addTearDown(() async {
      await _iterator.cancel();
      await _requests.close();
      client.dispose();
    });
  }

  final gateway = _Gateway();
  final spaces = <_Pending>[];

  /// Reactor listings served for `<messageId>/<emoji>`; unlisted keys are
  /// empty. A completer in [heldReactors] holds that listing until completed.
  final reactors = <String, List<String>>{};
  final heldReactors = <String, Completer<void>>{};
  final reactorRequests = <String>[];
  final _requests = StreamController<_Pending>();
  late final _iterator = StreamIterator(_requests.stream);
  late final AccordClient client;
  late final AccordAuthLoggedIn auth;

  Future<_Pending> next() async {
    expect(await _iterator.moveNext(), isTrue);
    return _iterator.current;
  }
}

class _Harness {
  _Harness(this.kind) {
    container = ProviderContainer(
      overrides: [
        accordAuthProvider.overrideWithValue(account.auth),
        settingsControllerProvider.overrideWith(_QuietSettings.new),
      ],
    );
    addTearDown(container.dispose);
    subscription = container.listen(provider, (_, _) {});
  }
  final _Kind kind;
  final account = _Account();
  late final ProviderContainer container;
  late final ProviderSubscription<List<AccordMessage>?> subscription;

  ProviderListenable<List<AccordMessage>?> get provider => switch (kind) {
    _Kind.messages => accordMessagesControllerProvider(_key, _channel),
    _Kind.replies => threadRepliesControllerProvider(_key, _channel, 'root'),
    _Kind.posts => forumPostsControllerProvider(_key, _channel),
  };
  AccordMessagesController get messages =>
      container.read(accordMessagesControllerProvider(_key, _channel).notifier);
  ThreadRepliesController get replies => container.read(
    threadRepliesControllerProvider(_key, _channel, 'root').notifier,
  );
  ForumPostsController get posts =>
      container.read(forumPostsControllerProvider(_key, _channel).notifier);
  List<AccordMessage>? get state => container.read(provider);
  List<String>? get ids => state?.map((m) => m.id).toList();
  bool get failed => container.read(messagesLoadFailedProvider(_key, _channel));

  Future<void> reload([AccordClient? client]) => switch (kind) {
    _Kind.messages => messages.reload(client ?? account.client),
    _Kind.replies => replies.reload(client ?? account.client),
    _Kind.posts => posts.reload(client ?? account.client),
  };
  void add(AccordMessage message) => switch (kind) {
    _Kind.messages => messages.addMessage(message),
    _Kind.replies => replies.addReply(message),
    _Kind.posts => posts.addPost(message),
  };
  void edit(AccordMessage message) => switch (kind) {
    _Kind.messages => messages.updateMessage(message),
    _Kind.replies => replies.updateReply(message),
    _Kind.posts => posts.updatePost(message),
  };
  void remove(String id) => switch (kind) {
    _Kind.messages => messages.removeMessage(id),
    _Kind.replies => replies.removeReply(id),
    _Kind.posts => posts.removePost(id),
  };
  Future<void> flush() async {
    // Drain async HTTP decoding/provider notifications, with no latency sleeps
    // or polling for a state value that could be produced by the wrong request.
    await pumpEventQueue();
    await container.pump();
  }

  Future<void> seed(List<AccordMessage> messages) async {
    (await account.next()).complete(messages);
    await flush();
  }

  Future<void> replace(_Account replacement) async {
    container.updateOverrides([
      accordAuthProvider.overrideWithValue(replacement.auth),
      settingsControllerProvider.overrideWith(_QuietSettings.new),
    ]);
    await container.pump();
  }
}

void main() {
  for (final kind in _Kind.values) {
    group(kind.name, () {
      for (final staleFails in [false, true]) {
        test('initial and reload results cannot supersede newest reload '
            '(stale failure: $staleFails)', () async {
          final h = _Harness(kind);
          final initial = await h.account.next();
          final firstReload = h.reload();
          final first = await h.account.next();
          final secondReload = h.reload();
          final second = await h.account.next();
          second.complete(_page('new'));
          await secondReload;
          final state = h.state;
          if (staleFails) {
            first.fail();
            initial.fail();
          } else {
            first.complete([_message('old-reload')]);
            initial.complete([_message('old-initial')]);
          }
          await firstReload;
          await h.flush();
          expect(h.state, same(state));
          expect(h.failed, isFalse);
          if (kind == _Kind.messages) expect(h.messages.hasMoreOlder, isTrue);
        });
      }

      test('stale success cannot clear the newest failure', () async {
        final h = _Harness(kind);
        final initial = await h.account.next();
        final reload = h.reload();
        (await h.account.next()).fail();
        await reload;
        final state = h.state;
        initial.complete(_page('old'));
        await h.flush();
        expect(h.state, same(state));
        if (kind == _Kind.messages) expect(h.failed, isTrue);
      });

      for (final reload in [false, true]) {
        test('creates, unknown edits and deletions survive '
            '${reload ? 'reconnect reload' : 'initial fetch'}', () async {
          final h = _Harness(kind);
          if (reload) await h.seed([_message('deleted'), _message('edited')]);
          final loading = reload ? h.reload() : null;
          final pending = await h.account.next();
          h.add(_message('created', 'live create'));
          h.edit(_message('created', 'live edit after create'));
          h.edit(_message('edited', 'live edit'));
          h.edit(_message('unrelated', 'must not insert'));
          h.remove('deleted');
          h.remove('never-cached');
          pending.complete([
            _message('deleted'),
            _message('edited', 'stale edit'),
            _message('never-cached'),
            _message('snapshot'),
          ]);
          if (loading != null) await loading;
          await h.flush();
          expect(h.ids, unorderedEquals(['edited', 'snapshot', 'created']));
          expect(
            h.state!.firstWhere((m) => m.id == 'edited').content,
            'live edit',
          );
          expect(
            h.state!.firstWhere((m) => m.id == 'created').content,
            'live edit after create',
          );
          expect(kind == _Kind.posts ? h.ids!.first : h.ids!.last, 'created');
        });
      }

      test('failed refresh retains live rows', () async {
        final h = _Harness(kind);
        await h.seed([_message('existing')]);
        final reload = h.reload();
        final pending = await h.account.next();
        h.add(_message('live'));
        pending.fail();
        await reload;
        expect(h.ids, unorderedEquals(['existing', 'live']));
      });

      test(
        'same-account client replacement invalidates initial request',
        () async {
          final h = _Harness(kind);
          final old = await h.account.next();
          h.remove(
            'new',
          ); // This old session's tombstone must also be discarded.
          final replacement = _Account();
          await h.replace(replacement);
          final current = await replacement.next();
          current.complete([_message('new')]);
          await h.flush();
          old.fail();
          await h.flush();
          expect(h.ids, ['new']);
          expect(h.failed, isFalse);
          // A caller holding the replaced client cannot even start a reload.
          await h.reload(h.account.client);
          expect(h.ids, ['new']);
        },
      );

      for (final differentServer in [false, true]) {
        test('isolates ${differentServer ? 'servers' : 'accounts'} with equal '
            'channel ids', () async {
          final h = _Harness(kind);
          final old = await h.account.next();
          final replacement = _Account(
            user: differentServer ? 'self' : 'other',
            host: differentServer
                ? 'other.example.test'
                : 'accord.example.test',
          );
          await h.replace(replacement);
          final key = replacement.auth.session.key;
          final ProviderListenable<List<AccordMessage>?> provider =
              switch (kind) {
                _Kind.messages => accordMessagesControllerProvider(
                  key,
                  _channel,
                ),
                _Kind.replies => threadRepliesControllerProvider(
                  key,
                  _channel,
                  'root',
                ),
                _Kind.posts => forumPostsControllerProvider(key, _channel),
              };
          h.container.listen(provider, (_, _) {});
          (await replacement.next()).complete([_message('other-account')]);
          await h.flush();
          old.complete([_message('private-old-account')]);
          await h.flush();
          expect(h.state, isNull);
          expect(h.container.read(provider)!.single.id, 'other-account');
          expect(h.failed, isFalse);
        });
      }

      test(
        'gateway READY supersedes history before delayed space sync',
        () async {
          final h = _Harness(kind);
          await h.seed(_page('seed'));
          addTearDown(
            handleAccordEvents(
              h.container.read(_refProvider),
              h.account.client,
              serverKey: _key,
              currentUserId: 'self',
              selfDomain: 'accord.example.test',
              isActive: () => true,
            ),
          );
          h.account.client.login();
          await h.flush();
          h.account.gateway.event('ready', {});
          await h.flush();
          expect(h.account.spaces, hasLength(1));

          final oldLoad = kind == _Kind.messages
              ? h.messages.loadOlder(h.account.client)
              : h.reload();
          final old = await h.account.next();
          // The first READY's space request is still pending. The second must
          // already count as reconnect and supersede all three history paths.
          h.account.gateway.event('ready', {});
          await h.flush();
          expect(h.account.spaces, hasLength(2));
          final fresh = await h.account.next();
          Map<String, dynamic> payload(String id, String content) => {
            'id': id,
            'channel_id': _channel,
            'space_id': 'space',
            'author_id': 'other',
            'content': content,
            if (kind == _Kind.replies) 'thread_id': 'root',
          };
          h.account.gateway.event('message.create', payload('live', 'created'));
          h.account.gateway.event(
            'message.update',
            payload('edited', 'live edit'),
          );
          h.account.gateway.event('message.delete', {
            'id': 'deleted',
            'channel_id': _channel,
          });
          await h.flush();
          fresh.complete([_message('edited', 'stale'), _message('deleted')]);
          await h.flush();
          old.complete([_message('obsolete'), _message('deleted')]);
          await oldLoad;
          await h.flush();
          expect(h.ids, unorderedEquals(['edited', 'live']));
          expect(
            h.state!.firstWhere((m) => m.id == 'edited').content,
            'live edit',
          );
          // Finish the unrelated requests before disposing the handler's Ref.
          for (final request in h.account.spaces) {
            request.fail();
          }
          await h.flush();
        },
      );

      test('disposed requests cannot publish failures', () async {
        final h = _Harness(kind);
        final old = await h.account.next();
        h.subscription.close();
        await h.container.pump();
        old.fail();
        await h.flush();
        expect(h.failed, isFalse);
      });
    });
  }

  group('pagination', () {
    for (final staleFails in [false, true]) {
      test('reload B supersedes page A; cleanup cannot clear page C '
          '(stale failure: $staleFails)', () async {
        final h = _Harness(_Kind.messages);
        await h.seed(_page('initial'));
        final a = h.messages.loadOlder(h.account.client);
        final pageA = await h.account.next();
        expect(pageA.request.url.queryParameters['before'], 'initial1');
        final b = h.reload();
        final pageB = await h.account.next();
        expect(await h.messages.loadOlder(h.account.client), 0);
        h.remove('deleted');
        pageB.complete(_page('new'));
        await b;
        final c = h.messages.loadOlder(h.account.client);
        final pageC = await h.account.next();
        expect(pageC.request.url.queryParameters['before'], 'new1');
        final state = h.state;
        var notifications = 0;
        final subscription = h.container.listen(
          h.provider,
          (_, _) => notifications++,
        );
        if (staleFails) {
          pageA.fail();
        } else {
          pageA.complete([_message('deleted'), _message('obsolete')]);
        }
        expect(await a, 0);
        expect(h.state, same(state));
        expect(notifications, 0);
        expect(h.messages.isLoadingOlder, isTrue);
        expect(h.messages.hasMoreOlder, isTrue);
        expect(h.failed, isFalse);
        pageC.complete([_message('older')]);
        expect(await c, 1);
        expect(h.ids!.first, 'older');
        expect(h.messages.isLoadingOlder, isFalse);
        expect(h.messages.hasMoreOlder, isFalse);
        subscription.close();
      });
    }

    test(
      'reconciles deleted/edited unknown rows and dedupes within/across pages',
      () async {
        final h = _Harness(_Kind.messages);
        await h.seed(_page('m'));
        final load = h.messages.loadOlder(h.account.client);
        final page = await h.account.next();
        expect(await h.messages.loadOlder(h.account.client), 0);
        h.remove('deleted');
        h.edit(_message('older', 'live edit'));
        h.edit(_message('m1', 'existing live edit'));
        h.add(_message('live'));
        page.complete([
          _message('m1', 'stale overlap'),
          _message('deleted'),
          _message('older'),
          _message('older'),
        ]);
        expect(await load, 1);
        expect(h.ids!.first, 'older');
        expect(h.ids!.last, 'live');
        expect(h.ids!.toSet().length, h.ids!.length);
        expect(h.state!.first.content, 'live edit');
        expect(
          h.state!.firstWhere((m) => m.id == 'm1').content,
          'existing live edit',
        );
        expect(h.ids, isNot(contains('deleted')));
        expect(h.messages.hasMoreOlder, isFalse);
      },
    );

    test(
      'replacement client resets pagination and rejects old page cleanup',
      () async {
        final h = _Harness(_Kind.messages);
        await h.seed(_page('old'));
        final load = h.messages.loadOlder(h.account.client);
        final old = await h.account.next();
        final replacement = _Account();
        await h.replace(replacement);
        expect(h.messages.isLoadingOlder, isFalse);
        (await replacement.next()).complete(_page('new'));
        await h.flush();
        final currentLoad = h.messages.loadOlder(replacement.client);
        final current = await replacement.next();
        old.complete([]);
        expect(await load, 0);
        expect(h.messages.isLoadingOlder, isTrue);
        expect(h.messages.hasMoreOlder, isTrue);
        expect(h.ids, isNot(contains('old1')));
        expect(await h.messages.loadOlder(h.account.client), 0);
        current.complete([]);
        await currentLoad;
        expect(h.messages.isLoadingOlder, isFalse);
        expect(h.messages.hasMoreOlder, isFalse);
      },
    );
  });

  group('live field changes during a reconnect reload', () {
    Future<(_Harness, Future<void>, _Pending)> reloading(_Kind kind) async {
      final h = _Harness(kind);
      await h.seed([_message('x', 'before disconnect')]);
      final loading = h.reload();
      return (h, loading, await h.account.next());
    }

    Future<AccordMessage> settle(
      _Harness h,
      Future<void> loading,
      _Pending pending,
    ) async {
      pending.complete([_message('x', 'edited while offline')]);
      await loading;
      await h.flush();
      return h.state!.single;
    }

    test('a reaction is replayed onto the fresh row', () async {
      final (h, loading, pending) = await reloading(_Kind.messages);
      h.account.reactors['x/emo_a'] = ['u1'];
      h.messages.applyReaction(
        'x',
        'emo_a',
        added: true,
        isOwn: false,
        userId: 'u1',
      );
      final x = await settle(h, loading, pending);
      expect(x.content, 'edited while offline');
      expect(x.reactions, hasLength(1));
      expect(x.reactions!.single.count, 1);
    });

    test('cleared reactions stay cleared on the fresh row', () async {
      final (h, loading, pending) = await reloading(_Kind.messages);
      h.messages.clearReactions('x');
      pending.complete([
        _message('x', 'edited while offline')
          ..reactions = [
            AccordReaction(
              emoji: {'name': 'thumbsup'},
              count: 2,
              includesMe: false,
            ),
          ],
      ]);
      await loading;
      await h.flush();
      final x = h.state!.single;
      expect(x.content, 'edited while offline');
      expect(x.reactions, isEmpty);
    });

    for (final kind in [_Kind.messages, _Kind.posts]) {
      test('a pin is replayed onto the fresh row (${kind.name})', () async {
        final (h, loading, pending) = await reloading(kind);
        if (kind == _Kind.messages) {
          await h.messages.pin(h.account.client, 'x');
        } else {
          await h.posts.togglePin(h.account.client, h.state!.single);
        }
        final x = await settle(h, loading, pending);
        expect(x.content, 'edited while offline');
        expect(x.pinned, isTrue);
      });
    }

    for (final kind in _Kind.values) {
      test(
        'a duplicate create echo keeps the fresh row (${kind.name})',
        () async {
          final (h, loading, pending) = await reloading(kind);
          h.add(_message('x', 'before disconnect'));
          final x = await settle(h, loading, pending);
          expect(x.content, 'edited while offline');
        },
      );

      test('an edit cannot resurrect a row deleted while offline '
          '(${kind.name})', () async {
        final h = _Harness(kind);
        await h.seed([_message('gone'), _message('kept')]);
        final loading = h.reload();
        final pending = await h.account.next();
        h.edit(_message('gone', 'live edit'));
        pending.complete([_message('kept')]);
        await loading;
        await h.flush();
        expect(h.ids, ['kept']);
      });
    }
  });

  group('reaction changes during a reconnect reload', () {
    AccordReaction reaction(String name, int count, {bool me = false}) =>
        AccordReaction(emoji: {'name': name}, count: count, includesMe: me);

    AccordMessage row(List<AccordReaction> reactions) =>
        _message('x', 'edited while offline')..reactions = reactions;

    Map<String, (int, bool)> summary(_Harness h) => {
      for (final r in h.state!.single.reactions ?? const <AccordReaction>[])
        r.emoji['name'] as String: (r.count, r.includesMe),
    };

    Future<(_Harness, Future<void>, _Pending)> reloading([
      List<AccordReaction> cached = const [],
    ]) async {
      final h = _Harness(_Kind.messages);
      await h.seed([_message('x', 'before disconnect')..reactions = cached]);
      final loading = h.reload();
      return (h, loading, await h.account.next());
    }

    Future<void> settle(
      _Harness h,
      Future<void> loading,
      _Pending pending,
      AccordMessage snapshot,
    ) async {
      pending.complete([snapshot]);
      await loading;
      await h.flush();
    }

    void other(_Harness h, String user, {bool added = true}) => h.messages
        .applyReaction('x', 'emo_a', added: added, isOwn: false, userId: user);

    for (final snapshotHasIt in [false, true]) {
      final when = snapshotHasIt ? 'includes' : 'predates';
      test('own reaction: unrelated server reactions survive and the live '
          'change is not double-counted (snapshot $when it)', () async {
        final (h, loading, pending) = await reloading();
        h.messages.applyReaction('x', 'emo_a', added: true, isOwn: true);
        // The gateway echo of the same reaction, qualified or not, is own too.
        h.messages.applyReaction(
          'x',
          'emo_a',
          added: true,
          isOwn: true,
          userId: 'self',
        );
        await settle(
          h,
          loading,
          pending,
          row([
            snapshotHasIt
                ? reaction('emo_a', 3, me: true)
                : reaction('emo_a', 2),
            reaction('emo_b', 4),
          ]),
        );
        expect(summary(h), {'emo_a': (3, true), 'emo_b': (4, false)});
        expect(h.state!.single.content, 'edited while offline');
        // Our own membership is settled by `includesMe`; no listing needed.
        expect(h.account.reactorRequests, isEmpty);
      });

      test(
        "another user's reaction: unrelated server reactions survive and "
        'the live change is not double-counted (snapshot $when it)',
        () async {
          final (h, loading, pending) = await reloading([reaction('emo_a', 1)]);
          h.account.reactors['x/emo_a'] = ['u1', 'u2'];
          final listing = h.account.heldReactors['x/emo_a'] = Completer();
          other(h, 'u2');
          await settle(
            h,
            loading,
            pending,
            row([
              reaction('emo_a', snapshotHasIt ? 2 : 1),
              reaction('emo_b', 4),
            ]),
          );
          // Until the listing settles it, the server count stands: never 3.
          expect(summary(h), {
            'emo_a': (snapshotHasIt ? 2 : 1, false),
            'emo_b': (4, false),
          });
          listing.complete();
          await h.flush();
          expect(summary(h), {'emo_a': (2, false), 'emo_b': (4, false)});
          expect(h.account.reactorRequests, ['x/emo_a']);
        },
      );

      test("another user's removal is applied per user "
          '(snapshot $when it)', () async {
        final (h, loading, pending) = await reloading([reaction('emo_a', 2)]);
        h.account.reactors['x/emo_a'] = snapshotHasIt ? ['u1'] : ['u1', 'u2'];
        other(h, 'u2', added: false);
        await settle(
          h,
          loading,
          pending,
          row([reaction('emo_a', snapshotHasIt ? 1 : 2), reaction('emo_b', 4)]),
        );
        expect(summary(h), {'emo_a': (1, false), 'emo_b': (4, false)});
      });
    }

    test('a change arriving while the listing is in flight is applied once, '
        'whether or not the listing includes it', () async {
      for (final listingHasIt in [false, true]) {
        final (h, loading, pending) = await reloading();
        final listing = h.account.heldReactors['x/emo_a'] = Completer();
        h.account.reactors['x/emo_a'] = ['u1', if (listingHasIt) 'u2', 'self'];
        other(h, 'u1');
        await settle(h, loading, pending, row([reaction('emo_a', 1)]));
        other(h, 'u2');
        h.messages.applyReaction('x', 'emo_a', added: true, isOwn: true);
        listing.complete();
        await h.flush();
        expect(summary(h), {
          'emo_a': (3, true),
        }, reason: 'listing $listingHasIt');
      }
    });

    test('a truncated or failed listing leaves the server count', () async {
      final (h, loading, pending) = await reloading();
      h.account.reactors['x/emo_a'] = [for (var i = 0; i < 100; i++) 'u$i'];
      other(h, 'u1');
      await settle(h, loading, pending, row([reaction('emo_a', 150)]));
      expect(summary(h), {'emo_a': (150, false)});
    });

    test('clearing one emoji keeps the other server reactions', () async {
      final (h, loading, pending) = await reloading([reaction('emo_a', 1)]);
      h.messages.clearReactionEmoji('x', 'emo_a');
      await settle(
        h,
        loading,
        pending,
        row([reaction('emo_a', 1), reaction('emo_b', 4)]),
      );
      expect(summary(h), {'emo_b': (4, false)});
    });

    test('reactions after a clear are replayed per user', () async {
      final (h, loading, pending) = await reloading([reaction('emo_a', 1)]);
      h.messages.clearReactions('x');
      h.messages.applyReaction('x', 'emo_b', added: true, isOwn: true);
      await settle(
        h,
        loading,
        pending,
        row([reaction('emo_a', 1), reaction('emo_b', 1, me: true)]),
      );
      expect(summary(h), {'emo_b': (1, true)});
    });

    test('a reaction on a message only in the snapshot is not lost', () async {
      final h = _Harness(_Kind.messages);
      await h.seed([_message('y')]);
      final loading = h.reload();
      final pending = await h.account.next();
      h.messages.applyReaction('x', 'emo_a', added: true, isOwn: true);
      pending.complete([
        _message('y'),
        row([reaction('emo_b', 4)]),
      ]);
      await loading;
      await h.flush();
      final x = h.state!.firstWhere((m) => m.id == 'x');
      expect(
        {
          for (final r in x.reactions!)
            r.emoji['name']: (r.count, r.includesMe),
        },
        {'emo_b': (4, false), 'emo_a': (1, true)},
      );
    });
  });

  test('a reload that fails still clears a superseded older-page spinner '
      'for list watchers', () async {
    final h = _Harness(_Kind.messages);
    await h.seed(_page('m'));
    final seen = <bool>[];
    h.container.listen(
      accordMessagesControllerProvider(_key, _channel),
      (_, _) => seen.add(h.messages.isLoadingOlder),
    );
    final older = h.messages.loadOlder(h.account.client);
    final page = await h.account.next();
    expect(seen.last, isTrue);
    final reload = h.reload();
    (await h.account.next()).fail();
    await reload;
    page.complete(_page('old'));
    expect(await older, 0);
    await h.flush();
    expect(h.messages.isLoadingOlder, isFalse);
    // The watcher was told after the flag cleared, so a header that watches
    // only the list rebuilds without its spinner.
    expect(seen.last, isFalse);
  });

  for (final mutation in ['edit', 'pin', 'react']) {
    test('a live $mutation of an older-page row during a reload does not '
        'append it to the newest page; pagination restores it', () async {
      final h = _Harness(_Kind.messages);
      await h.seed(_page('new'));
      final older = h.messages.loadOlder(h.account.client);
      (await h.account.next()).complete(_page('old'));
      expect(await older, 50);
      final reload = h.reload();
      final pending = await h.account.next();
      switch (mutation) {
        case 'edit':
          h.edit(_message('old30', 'live edit'));
        case 'pin':
          await h.messages.pin(h.account.client, 'old30');
        default:
          h.messages.applyReaction('old30', 'emo_a', added: true, isOwn: true);
      }
      pending.complete(_page('new'));
      await reload;
      await h.flush();
      expect(h.ids, [for (var i = 1; i <= 50; i++) 'new$i']);
      final restore = h.messages.loadOlder(h.account.client);
      final page = await h.account.next();
      expect(page.request.url.queryParameters['before'], 'new1');
      page.complete([
        for (var i = 50; i > 0; i--)
          i == 30
              ? (_message('old30', 'server copy')
                  ..pinned = mutation == 'pin'
                  ..reactions = [
                    if (mutation == 'react')
                      AccordReaction(
                        emoji: {'name': 'emo_a'},
                        count: 1,
                        includesMe: true,
                      ),
                  ])
              : _message('old$i'),
      ]);
      expect(await restore, 50);
      expect(h.ids, [
        for (var i = 1; i <= 50; i++) 'old$i',
        for (var i = 1; i <= 50; i++) 'new$i',
      ]);
      final old30 = h.state!.firstWhere((m) => m.id == 'old30');
      expect(old30.content, 'server copy');
      if (mutation == 'pin') expect(old30.pinned, isTrue);
      if (mutation == 'react') expect(old30.reactions!.single.count, 1);
    });
  }
}
