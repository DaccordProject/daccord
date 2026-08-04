import 'package:flutter/widgets.dart';

/// Returns focus to [node] once the current frame has been laid out.
///
/// Every composer in the app disables its `TextField` while a send is in flight
/// (`enabled: !_sending`), and submitting via [TextInputAction.send] unfocuses
/// the field. Restoring focus straight after `setState(() => _sending = false)`
/// looks right but is a silent no-op: `TextField` pushes
/// `FocusNode.canRequestFocus = false` while it is disabled, and
/// `FocusNode.requestFocus` returns early — without queueing — when
/// `canRequestFocus` is false. The rebuild that re-enables the field (and with
/// it `canRequestFocus`) has not run yet at that point, so the request is
/// dropped and the user has to click back into the field for every message.
///
/// Deferring to after the frame lets the field re-enable first, so the request
/// lands.
void refocusAfterFrame(FocusNode node) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (node.context != null) node.requestFocus();
  });
}
