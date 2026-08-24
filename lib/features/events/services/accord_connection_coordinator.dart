import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/events/services/accord_event_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Owns the gateway-to-state subscriptions for every live server connection.
///
/// Authentication publishes clients and sessions; this service independently
/// coordinates their event streams with feature state. Keeping its own [Ref]
/// means event callbacks can use ordinary declared provider reads instead of
/// reaching through the auth provider's container to evade a dependency cycle.
final accordConnectionCoordinatorProvider =
    Provider<AccordConnectionCoordinator>((ref) {
      final coordinator = AccordConnectionCoordinator(ref);
      ref.onDispose(coordinator.dispose);
      return coordinator;
    });

class AccordConnectionCoordinator {
  AccordConnectionCoordinator(
    this._ref, {
    AccordEventBinder bindEvents = handleAccordEvents,
  }) : _bindEvents = bindEvents;

  final Ref _ref;
  final AccordEventBinder _bindEvents;
  final Map<String, VoidCallback> _eventDisposers = {};

  /// Starts coordinating gateway events for [session]. Replacing an existing
  /// binding for the same server key first cancels all of its subscriptions.
  void attach({
    required AccordClient client,
    required AccordSession session,
    required bool Function() isActive,
  }) {
    detach(session.key);
    _eventDisposers[session.key] = _bindEvents(
      _ref,
      client,
      serverKey: session.key,
      currentUserId: session.userId,
      selfDomain: session.server.homeDomain,
      isActive: isActive,
    );
  }

  /// Stops all event fanout for one connection without disposing its client.
  void detach(String serverKey) => _eventDisposers.remove(serverKey)?.call();

  /// Stops event fanout for every connection.
  void detachAll() {
    for (final disposeEvents in _eventDisposers.values) {
      disposeEvents();
    }
    _eventDisposers.clear();
  }

  @visibleForTesting
  Set<String> get attachedServerKeys => Set.unmodifiable(_eventDisposers.keys);

  void dispose() => detachAll();
}

@visibleForTesting
typedef AccordEventBinder =
    VoidCallback Function(
      Ref ref,
      AccordClient client, {
      required String serverKey,
      required String currentUserId,
      required String selfDomain,
      required bool Function() isActive,
    });
