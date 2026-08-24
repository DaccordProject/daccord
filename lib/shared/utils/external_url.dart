import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

typedef ExternalUrlLauncher = Future<bool> Function(Uri uri);

enum ExternalUrlOpenResult { opened, blocked, cancelled, failed }

enum MessageMediaUrlDisposition { trusted, consentRequired, blocked }

/// The result of applying the message-media URL policy to an untrusted source.
class MessageMediaUrlDecision {
  const MessageMediaUrlDecision._(this.disposition, this.uri);

  const MessageMediaUrlDecision.blocked()
    : this._(MessageMediaUrlDisposition.blocked, null);

  final MessageMediaUrlDisposition disposition;
  final Uri? uri;
}

/// Parses an external web URL under the policy used for untrusted links.
///
/// Non-web schemes intentionally have no opt-in here. A future use case for
/// one must provide its own scheme-specific UI and confirmation rather than
/// making message or server content capable of invoking it.
Uri? tryParseExternalWebUrl(String? value) {
  final candidate = value?.trim();
  if (candidate == null || candidate.isEmpty) return null;

  final uri = Uri.tryParse(candidate);
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      (uri.scheme.toLowerCase() != 'http' &&
          uri.scheme.toLowerCase() != 'https')) {
    return null;
  }
  return uri;
}

/// Resolves and classifies an image URL supplied by untrusted message content.
///
/// HTTP(S) images on the configured CDN origin may load immediately. Other
/// HTTP(S) origins require a user gesture before they are fetched. Everything
/// else is blocked, including local files, assets/resources, custom schemes,
/// protocol-relative URLs, and Windows UNC paths. Relative paths are accepted
/// only when a valid trusted CDN base is available.
MessageMediaUrlDecision classifyMessageMediaUrl(
  String? value, {
  String? trustedBaseUrl,
}) {
  final candidate = value?.trim();
  if (candidate == null ||
      candidate.isEmpty ||
      candidate.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
      candidate.contains(r'\')) {
    return const MessageMediaUrlDecision.blocked();
  }

  final parsed = Uri.tryParse(candidate);
  if (parsed == null || parsed.userInfo.isNotEmpty) {
    return const MessageMediaUrlDecision.blocked();
  }

  final parsedTrustedBase = tryParseExternalWebUrl(trustedBaseUrl);
  final trustedBase = parsedTrustedBase?.userInfo.isEmpty == true
      ? parsedTrustedBase
      : null;
  if (!parsed.hasScheme) {
    // `//host/path` is network-path syntax, and is also how POSIX-looking UNC
    // paths can reach platform file handlers. Never reinterpret it as a CDN
    // relative path.
    if (parsed.hasAuthority || trustedBase == null) {
      return const MessageMediaUrlDecision.blocked();
    }
    final resolved = tryParseExternalWebUrl(
      AccordCDN.resolvePath(candidate, cdnUrl: trustedBase.toString()),
    );
    if (resolved == null || !_sameWebOrigin(resolved, trustedBase)) {
      return const MessageMediaUrlDecision.blocked();
    }
    return MessageMediaUrlDecision._(
      MessageMediaUrlDisposition.trusted,
      resolved,
    );
  }

  final webUri = tryParseExternalWebUrl(candidate);
  if (webUri == null || webUri.userInfo.isNotEmpty) {
    return const MessageMediaUrlDecision.blocked();
  }
  return MessageMediaUrlDecision._(
    trustedBase != null && _sameWebOrigin(webUri, trustedBase)
        ? MessageMediaUrlDisposition.trusted
        : MessageMediaUrlDisposition.consentRequired,
    webUri,
  );
}

bool _sameWebOrigin(Uri a, Uri b) =>
    a.scheme.toLowerCase() == b.scheme.toLowerCase() &&
    a.host.toLowerCase() == b.host.toLowerCase() &&
    a.port == b.port;

/// Confirms and opens an untrusted HTTP(S) URL in the platform browser.
///
/// The confirmation names the parsed destination host, which avoids trusting
/// potentially disguised link text. Invalid, relative, and non-web URLs are
/// blocked before the launcher is called.
Future<ExternalUrlOpenResult> openExternalUrl(
  BuildContext context,
  String? value, {
  ExternalUrlLauncher? launcher,
}) async {
  final uri = tryParseExternalWebUrl(value);
  if (uri == null) {
    _showMessage(context, 'Only valid HTTP and HTTPS links can be opened.');
    return ExternalUrlOpenResult.blocked;
  }

  final confirmed = await showConfirmDialog(
    context,
    title: 'Open external link?',
    message: 'This link will open in your browser.\n\nDestination: ${uri.host}',
    confirmLabel: 'Open link',
  );
  if (confirmed != true || !context.mounted) {
    return ExternalUrlOpenResult.cancelled;
  }

  try {
    final launched = await (launcher ?? _launchExternalUrl)(uri);
    if (launched) return ExternalUrlOpenResult.opened;
  } catch (_) {
    // Report the failure below without interpolating the untrusted full URL.
  }

  if (context.mounted) {
    _showMessage(context, "Couldn't open the link to ${uri.host}.");
  }
  return ExternalUrlOpenResult.failed;
}

Future<bool> _launchExternalUrl(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

void _showMessage(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
}
