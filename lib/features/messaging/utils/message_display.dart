import 'package:accordkit/accordkit.dart';

/// Join messages may contain an outdated name (including a legacy email
/// username). Resolve their text from the same current name as the header,
/// including the safe "Unknown" fallback while the author is loading.
String accordMessageText(AccordMessage message, {required String authorName}) {
  if (message.type == 'member_join') {
    return '$authorName joined the server.';
  }
  return message.content;
}
