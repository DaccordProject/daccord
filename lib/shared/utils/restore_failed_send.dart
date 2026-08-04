import 'package:flutter/widgets.dart';

/// Puts [text] back into [controller] after a send failed.
///
/// Composers clear optimistically when a send starts (the field stays enabled
/// and focused for the whole round-trip, so it has to be ready for the next
/// message immediately), which means a failure has to hand the message back or
/// the user loses what they typed.
///
/// Because the field is live during the send, the user may have started typing
/// the next message before the failure came back. Two cases:
///
/// * the field is still empty — the common one — so the failed text is restored
///   as-is with the caret at the end, ready to fix and retry;
/// * the user typed something, so the failed text is *prepended* (separated by
///   a newline) rather than overwriting it, and their caret/selection is
///   shifted along so they can carry on typing where they left off.
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
