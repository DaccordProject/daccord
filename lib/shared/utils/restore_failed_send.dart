import 'package:flutter/widgets.dart';

/// Puts [text] back into [controller] after a send failed.
///
/// Composers clear optimistically and stay editable during the send, so if the
/// user already started the next message the failed text is prepended on its
/// own line and their selection is shifted to match.
void restoreFailedSend(TextEditingController controller, String text) {
  if (text.isEmpty) return;
  final current = controller.text;
  if (current.isEmpty) {
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    return;
  }
  final prefix = '$text\n';
  final selection = controller.selection;
  controller.value = TextEditingValue(
    text: '$prefix$current',
    selection: selection.isValid
        ? TextSelection(
            baseOffset: selection.baseOffset + prefix.length,
            extentOffset: selection.extentOffset + prefix.length,
          )
        : TextSelection.collapsed(offset: prefix.length + current.length),
  );
}
