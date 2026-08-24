import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

typedef ExternalUrlLauncher = Future<bool> Function(Uri uri);

enum ExternalUrlOpenResult { opened, blocked, cancelled, failed }

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
