import 'package:bonfire/shared/utils/external_url.dart';
import 'package:flutter/material.dart';

typedef MessageMediaBuilder = Widget Function(BuildContext context, String url);

/// Applies the untrusted-message media policy before constructing an image.
///
/// A first-party CDN image is built immediately. A third-party HTTP(S) image
/// is built only after the user explicitly opts in, while local/custom URI
/// schemes never reach [builder]. Set [allowExternalConsent] to false for tiny
/// decorative images where a meaningful consent affordance cannot fit.
class MessageMediaGate extends StatefulWidget {
  const MessageMediaGate({
    super.key,
    required this.source,
    required this.trustedBaseUrl,
    required this.builder,
    this.blockedPlaceholder = const SizedBox.shrink(),
    this.allowExternalConsent = true,
    this.compactConsent = false,
  });

  final String? source;
  final String? trustedBaseUrl;
  final MessageMediaBuilder builder;
  final Widget blockedPlaceholder;
  final bool allowExternalConsent;
  final bool compactConsent;

  @override
  State<MessageMediaGate> createState() => _MessageMediaGateState();
}

class _MessageMediaGateState extends State<MessageMediaGate> {
  bool _externalAllowed = false;

  @override
  void didUpdateWidget(covariant MessageMediaGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.trustedBaseUrl != widget.trustedBaseUrl) {
      _externalAllowed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final decision = classifyMessageMediaUrl(
      widget.source,
      trustedBaseUrl: widget.trustedBaseUrl,
    );
    final uri = decision.uri;
    switch (decision.disposition) {
      case MessageMediaUrlDisposition.trusted:
        return widget.builder(context, uri!.toString());
      case MessageMediaUrlDisposition.blocked:
        return widget.blockedPlaceholder;
      case MessageMediaUrlDisposition.consentRequired:
        if (_externalAllowed) return widget.builder(context, uri!.toString());
        if (!widget.allowExternalConsent) return widget.blockedPlaceholder;
        return _ConsentPrompt(
          host: uri!.host,
          compact: widget.compactConsent,
          onLoad: () => setState(() => _externalAllowed = true),
        );
    }
  }
}

class _ConsentPrompt extends StatelessWidget {
  const _ConsentPrompt({
    required this.host,
    required this.compact,
    required this.onLoad,
  });

  final String host;
  final bool compact;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    final label = 'Load external image from $host';
    if (compact) {
      return Tooltip(
        message: label,
        child: IconButton(
          key: const ValueKey('load-external-message-image'),
          tooltip: label,
          onPressed: onLoad,
          icon: const Icon(Icons.visibility_off_outlined),
        ),
      );
    }
    return Container(
      key: const ValueKey('external-message-image-consent'),
      padding: const EdgeInsets.all(8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: TextButton.icon(
        key: const ValueKey('load-external-message-image'),
        onPressed: onLoad,
        icon: const Icon(Icons.visibility_off_outlined),
        label: Text(label),
      ),
    );
  }
}
