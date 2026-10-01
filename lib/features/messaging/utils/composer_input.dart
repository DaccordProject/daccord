/// Keyboard and text-editing helpers behind the message composer.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Linux: the composer field uses `TextInputAction.newline`, and the Enter
/// roles are inverted compared with Windows and macOS.
///
/// - **Shift+Enter** is never claimed by the composer. GTK's input method sees
///   it first (`fl_text_input_handler_filter_keypress`) and commits any
///   composition, even one Dart can't see (Ctrl+Shift+U hex entry, a pending
///   IBus key); otherwise the embedder inserts `\n` into its own model, queued
///   in order with any keys typed after it. A `newline` action on a multiline
///   field does nothing in Dart, so there is nothing to race.
/// - **Plain Enter** (no modifiers, no reported composition) is claimed, and
///   the send waits on the composer's input barrier for GTK to deliver every
///   edit queued before it.
///
/// The `send` action can't be used instead: `EditableText._finalizeEditing`
/// always restarts the text-input connection for it, and GTK discards updates
/// still queued for the old client, losing keys typed right after Shift+Enter.
///
/// Known limitations: a plain Enter during a composition GTK hasn't reported
/// sends instead of committing; an input method that commits asynchronously
/// (IBus in async mode) can deliver a key typed just before Enter after the
/// barrier; and Enter with Ctrl or Alt inserts a newline here, where it sends
/// on Windows and macOS.
bool get composerUsesNativeNewlines =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

bool isEnterKey(KeyEvent event) =>
    event.logicalKey == LogicalKeyboardKey.enter ||
    event.logicalKey == LogicalKeyboardKey.numpadEnter;

/// Whether [event] is Shift+Enter (either Enter key, no other modifiers).
///
/// The composer's action is `send` so mobile keyboards show a Send key. The
/// desktop embedders (Linux `fl_text_input_handler.cc`, Windows
/// `text_input_plugin.cc`, macOS `FlutterTextInputPlugin.mm`) only insert a
/// newline for Enter when the action is `newline`, and they ignore Shift, so a
/// plain TextField sends on Shift+Enter. On Windows and macOS the composer
/// claims the chord itself before it reaches the embedder.
bool isShiftEnterChord(KeyEvent event, HardwareKeyboard keys) =>
    _isEnterWith(event, keys, shift: true);

/// Whether [event] is Enter (either Enter key) with no modifiers held.
bool isPlainEnter(KeyEvent event, HardwareKeyboard keys) =>
    _isEnterWith(event, keys, shift: false);

bool _isEnterWith(
  KeyEvent event,
  HardwareKeyboard keys, {
  required bool shift,
}) =>
    isEnterKey(event) &&
    keys.isShiftPressed == shift &&
    !keys.isControlPressed &&
    !keys.isMetaPressed &&
    !keys.isAltPressed;

/// The text to keep from a key claimed while a Linux plain-Enter send waits
/// for GTK, or null. Shift+Enter keeps its newline; plain Enter (the draft is
/// already being sent), shortcuts and non-printing keys keep nothing.
String? bufferedKeyText(KeyEvent event, HardwareKeyboard keys) {
  if (keys.isControlPressed || keys.isMetaPressed || keys.isAltPressed) {
    return null;
  }
  if (isEnterKey(event)) return keys.isShiftPressed ? '\n' : null;
  final character = event.character;
  if (character == null || character.isEmpty) return null;
  if (character.runes.any((r) => r < 0x20 || r == 0x7f)) return null;
  return character;
}

/// Whether the UTF-16 [code] continues a word, so an `@` or `#` right after it
/// (as in `email@host`) isn't a mention. Non-ASCII counts as a word character.
bool isMentionWordChar(int code) =>
    (code >= 0x30 && code <= 0x39) || // 0-9
    (code >= 0x41 && code <= 0x5A) || // A-Z
    (code >= 0x61 && code <= 0x7A) || // a-z
    code == 0x5F || // _
    code > 0x7F;

/// The `@` mention being typed at [selection] in [text], or null. Mirrors the
/// reference composer's `_find_mention_trigger`: the nearest `@` before the
/// caret that starts the text or follows a non-word character, with no
/// whitespace between it and the caret. `[start, end)` covers the `@` and the
/// lowercased [query] after it.
({int start, int end, String query})? findMentionTrigger(
  String text,
  TextSelection selection,
) {
  if (!selection.isValid || !selection.isCollapsed) return null;
  final caret = selection.baseOffset;
  for (var i = caret - 1; i >= 0; i--) {
    final ch = text[i];
    if (ch == '@') {
      if (i > 0 && isMentionWordChar(text.codeUnitAt(i - 1))) return null;
      return (
        start: i,
        end: caret,
        query: text.substring(i + 1, caret).toLowerCase(),
      );
    }
    if (ch == ' ' || ch == '\t' || ch == '\n') return null;
  }
  return null;
}

/// [value] with [text] replacing its selection (appended when there is none),
/// and the caret placed after the inserted text.
TextEditingValue insertAtSelection(TextEditingValue value, String text) {
  final selection = value.selection;
  final start = selection.isValid ? selection.start : value.text.length;
  final end = selection.isValid ? selection.end : value.text.length;
  return TextEditingValue(
    text: value.text.replaceRange(start, end, text),
    selection: TextSelection.collapsed(offset: start + text.length),
  );
}
