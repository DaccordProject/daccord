import 'accord_error.dart';

/// The application owns local assessment and any warning confirmation.
typedef MessageSendGuard = Future<MessageSendCheck> Function(
    String channelId, Map<String, dynamic> snapshot);

/// Permission for precisely one immutable outgoing snapshot. Rechecked after
/// asynchronous encryption, immediately before the network write.
class MessageSendCheck {
  const MessageSendCheck.allow({this.isCurrent}) : error = null;
  const MessageSendCheck.hold(this.error) : isCurrent = null;

  final AccordError? error;
  final bool Function()? isCurrent;

  AccordError? get failure =>
      error ??
      (isCurrent?.call() == false
          ? AccordError(
              code: 'message_check_stale',
              message: 'Message checks changed. Please try sending again.')
          : null);
}
