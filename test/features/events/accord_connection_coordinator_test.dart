import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/events/services/accord_connection_coordinator.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('coordinator owns and replaces server event subscriptions', () async {
    var bindings = 0;
    var disposals = 0;
    late final Provider<AccordConnectionCoordinator> provider;
    provider = Provider((ref) {
      return AccordConnectionCoordinator(
        ref,
        bindEvents:
            (
              _,
              _, {
              required serverKey,
              required currentUserId,
              required selfDomain,
              required isActive,
            }) {
              bindings++;
              expect(serverKey, contains('@https://accord.example.test'));
              expect(currentUserId, 'self');
              expect(selfDomain, 'accord.example.test');
              expect(isActive(), isTrue);
              return () => disposals++;
            },
      );
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final coordinator = container.read(provider);
    final server = AccordServer.fromBaseUrl('https://accord.example.test');
    final session = AccordSession(
      server: server,
      token: 'token',
      userId: 'self',
      username: 'Self',
    );
    final firstClient = AccordClient(
      token: 'first',
      baseUrl: server.baseUrl,
      gatewayUrl: server.gatewayUrl,
      cdnUrl: server.cdnUrl,
    );
    final replacementClient = AccordClient(
      token: 'replacement',
      baseUrl: server.baseUrl,
      gatewayUrl: server.gatewayUrl,
      cdnUrl: server.cdnUrl,
    );
    addTearDown(firstClient.dispose);
    addTearDown(replacementClient.dispose);

    coordinator.attach(
      client: firstClient,
      session: session,
      isActive: () => true,
    );
    expect(coordinator.attachedServerKeys, {session.key});

    coordinator.attach(
      client: replacementClient,
      session: session,
      isActive: () => true,
    );
    expect(bindings, 2);
    expect(disposals, 1);

    coordinator.detach(session.key);
    expect(coordinator.attachedServerKeys, isEmpty);
    expect(disposals, 2);
  });
}
