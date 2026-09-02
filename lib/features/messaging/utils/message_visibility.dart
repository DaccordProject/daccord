import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/controllers/hidden_messages.dart';
import 'package:bonfire/features/user/controllers/blocked_users.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a message surface must keep out of the user's view: the messages they
/// reported, and everything written by an account they blocked (#290).
///
/// Every surface that lists messages — the pane, the thread view, the pinned
/// list — filters through this, so a report or a block applies everywhere
/// instead of only where it was made.
class MessageVisibility {
  const MessageVisibility({
    required this.hiddenMessageIds,
    required this.blockedAuthorIds,
  });

  /// Nothing filtered — for surfaces built without a provider scope.
  static const none = MessageVisibility(
    hiddenMessageIds: {},
    blockedAuthorIds: {},
  );

  final Set<String> hiddenMessageIds;
  final Set<String> blockedAuthorIds;

  bool get filtersNothing =>
      hiddenMessageIds.isEmpty && blockedAuthorIds.isEmpty;

  /// Whether [message] should still be shown.
  bool shows(AccordMessage message) =>
      !hiddenMessageIds.contains(message.id) &&
      !blockedAuthorIds.contains(message.authorId);

  /// [messages] without the hidden/blocked ones. Returns the same list when
  /// there is nothing to filter, so an untouched pane doesn't copy its list on
  /// every build.
  List<AccordMessage> filter(List<AccordMessage> messages) =>
      filtersNothing ? messages : messages.where(shows).toList();
}

/// Watches the hidden-message and blocked-account sets for the active
/// connection. Call from `build` — the result can then be applied inside nested
/// builders (a `FutureBuilder`, a list item builder) where watching is not
/// allowed.
extension MessageVisibilityRef on WidgetRef {
  MessageVisibility watchMessageVisibility() => MessageVisibility(
    hiddenMessageIds: watch(hiddenMessagesControllerProvider),
    blockedAuthorIds: watch(
      blockedUsersControllerProvider(readActiveServerKey() ?? ''),
    ),
  );
}
