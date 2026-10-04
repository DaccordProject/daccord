import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/utils/message_display.dart';
import 'package:bonfire/features/messaging/views/box/accord_message_content.dart';
import 'package:bonfire/shared/utils/style/markdown/stylesheet.dart';
import 'package:flutter/material.dart';

/// System join text uses the resolved author name as literal text, so names
/// cannot become Markdown links or mentions. Regular messages keep Markdown.
class MessageBody extends StatelessWidget {
  const MessageBody({
    super.key,
    required this.message,
    required this.authorName,
    this.spaceId,
  });

  final AccordMessage message;
  final String authorName;
  final String? spaceId;

  @override
  Widget build(BuildContext context) {
    final content = accordMessageText(message, authorName: authorName);
    if (message.type == 'member_join') {
      return Text(content, style: getMarkdownStyleSheet(context).paragraph);
    }
    return AccordMessageContent(content: content, spaceId: spaceId);
  }
}
