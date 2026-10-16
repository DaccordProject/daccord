import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/controllers/hidden_messages.dart';
import 'package:bonfire/features/user/controllers/blocked_users.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a message surface must keep out of the user's view: the messages they
/// reported (#290), and — in direct messages only — everything written by an
/// account they blocked.
///
/// Every surface that lists messages — the pane, the thread view, the pinned
/// list — filters through this, so a report applies everywhere instead of only
/// where it was made. A block stops the account reaching you directly, but it
/// doesn't rewrite the conversation in a shared channel: their space messages
/// stay visible (without notifying), so replies to them still make sense.
class MessageVisibility {
  const MessageVisibility({
    required this.hiddenMessageIds,
    required this.blockedAuthorIds,
  });

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

/// Watches the hidden-message set — and, for a direct message, the
/// blocked-account set — of the active connection. [directMessage] is whether
/// the surface shows a DM / group-DM channel (no parent space). Call from
/// `build` — the result can then be applied inside nested builders (a
/// `FutureBuilder`, a list item builder) where watching is not allowed.
extension MessageVisibilityRef on WidgetRef {
  MessageVisibility watchMessageVisibility({required bool directMessage}) =>
      MessageVisibility(
        hiddenMessageIds: watch(hiddenMessagesControllerProvider),
        blockedAuthorIds: directMessage
            ? watch(blockedUsersControllerProvider(readActiveServerKey() ?? ''))
            : const {},
      );
}
