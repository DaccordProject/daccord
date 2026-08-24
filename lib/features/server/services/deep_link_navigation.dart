import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/events/controllers/connection.dart';
import 'package:bonfire/features/server/utils/server_uri.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A destination held while authentication, the owning server, or its space
/// cache is still starting. Keeping the server qualifier for connect links
/// prevents a link from being applied to whichever account happens to be
/// active at the time.
class PendingDeepLinkDestination {
  const PendingDeepLinkDestination({
    this.serverBaseUrl,
    this.spaceId,
    this.spaceName,
    this.channelId,
    this.channelName,
    this.messageId,
  });

  final String? serverBaseUrl;
  final String? spaceId;
  final String? spaceName;
  final String? channelId;
  final String? channelName;
  final String? messageId;

  /// Converts only routes that select an in-app destination. Invite and
  /// federation links keep their existing purpose-specific flows.
  static PendingDeepLinkDestination? fromParsed(ParsedServerUrl parsed) {
    switch (parsed.route) {
      case 'navigate':
        final spaceId = parsed.spaceId;
        if (spaceId == null || spaceId.isEmpty) return null;
        return PendingDeepLinkDestination(
          spaceId: spaceId,
          channelId: parsed.channelId,
          messageId: parsed.messageId,
        );
      case 'connect':
        final baseUrl = parsed.server?.baseUrl;
        if (baseUrl == null || baseUrl.isEmpty) return null;
        return PendingDeepLinkDestination(
          serverBaseUrl: baseUrl,
          spaceName: parsed.spaceName,
          channelName: parsed.channelName,
        );
      default:
        return null;
    }
  }
}

class ResolvedDeepLinkDestination {
  const ResolvedDeepLinkDestination({
    required this.serverKey,
    this.spaceId,
    this.channelId,
    this.channelName,
    this.messageId,
  });

  final String serverKey;
  final String? spaceId;
  final String? channelId;
  final String? channelName;
  final String? messageId;

  /// The home route carries the destination until its channel/message caches
  /// have mounted. Query construction also gives router tests one canonical
  /// representation of a fully resolved deep link.
  Uri get route {
    final query = <String, String>{};
    if (spaceId case final value?) query['space'] = value;
    if (channelId case final value?) query['channel'] = value;
    if (channelName case final value?) query['channelName'] = value;
    if (messageId case final value?) query['message'] = value;
    return Uri(path: '/spaces', queryParameters: query);
  }
}

sealed class DeepLinkResolution {
  const DeepLinkResolution();
}

class DeepLinkWaiting extends DeepLinkResolution {
  const DeepLinkWaiting();
}

class DeepLinkUnavailable extends DeepLinkResolution {
  const DeepLinkUnavailable(this.message);

  final String message;
}

class DeepLinkResolved extends DeepLinkResolution {
  const DeepLinkResolved(this.destination);

  final ResolvedDeepLinkDestination destination;
}

/// Resolves a pending destination only from a READY connection's authoritative
/// space cache. Missing connections remain pending because background account
/// restoration is asynchronous; a known READY server with a missing named
/// space is a final, user-visible failure.
DeepLinkResolution resolveDeepLinkDestination(
  PendingDeepLinkDestination pending,
  ConnectionsState connections,
) {
  final targetBaseUrl = pending.serverBaseUrl;
  if (targetBaseUrl != null) {
    AccordConnection? owner;
    for (final connection in connections.connections) {
      if (connection.session.server.baseUrl == targetBaseUrl) {
        owner = connection;
        break;
      }
    }
    if (owner == null ||
        owner.status != ConnectionStatus.ready ||
        !owner.spacesReady) {
      return const DeepLinkWaiting();
    }
    final requestedSpace = pending.spaceName;
    if (requestedSpace == null || requestedSpace.isEmpty) {
      return DeepLinkResolved(
        ResolvedDeepLinkDestination(serverKey: owner.key),
      );
    }
    final matches = owner.spaces
        .where(
          (space) =>
              space.id == requestedSpace ||
              space.slug == requestedSpace ||
              space.name == requestedSpace,
        )
        .toList();
    if (matches.length != 1) {
      return DeepLinkUnavailable(
        matches.isEmpty
            ? 'The linked space is not available on this server.'
            : 'The linked space name is ambiguous on this server.',
      );
    }
    return DeepLinkResolved(
      ResolvedDeepLinkDestination(
        serverKey: owner.key,
        spaceId: matches.single.id,
        channelName: pending.channelName,
      ),
    );
  }

  final spaceId = pending.spaceId;
  if (spaceId == null || spaceId.isEmpty) {
    return const DeepLinkUnavailable('The link has no space destination.');
  }
  final owners = connections.connections
      .where(
        (connection) =>
            connection.status == ConnectionStatus.ready &&
            connection.spacesReady &&
            connection.spaces.any((space) => space.id == spaceId),
      )
      .toList();
  if (owners.isEmpty) return const DeepLinkWaiting();
  if (owners.length > 1) {
    return const DeepLinkUnavailable(
      'The linked space exists on more than one connected server.',
    );
  }
  return DeepLinkResolved(
    ResolvedDeepLinkDestination(
      serverKey: owners.single.key,
      spaceId: spaceId,
      channelId: pending.channelId,
      messageId: pending.messageId,
    ),
  );
}

class PendingDeepLinkController extends Notifier<PendingDeepLinkDestination?> {
  @override
  PendingDeepLinkDestination? build() => null;

  void hold(PendingDeepLinkDestination destination) => state = destination;

  void clear() => state = null;
}

final pendingDeepLinkProvider =
    NotifierProvider<PendingDeepLinkController, PendingDeepLinkDestination?>(
      PendingDeepLinkController.new,
    );
