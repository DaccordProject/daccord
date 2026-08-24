import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/shared/utils/external_url.dart';
import 'package:flutter/material.dart';

/// A server's Terms-of-Service registration gate, read from its public
/// settings: whether acceptance is required, plus the ToS link and/or inline
/// text to show. Shared by the login screen and the Add-a-Server dialog, which
/// each keep the values in their own form state.
typedef TosConfig = ({bool enabled, String? url, String? text});

/// Fetches [server]'s ToS config through [auth]'s public-settings read. A
/// missing or failed settings fetch yields a disabled gate (no URL, no text).
Future<TosConfig> fetchTosConfig(AccordAuth auth, AccordServer server) async {
  final settings = await auth.fetchServerSettings(server);
  return (
    enabled: settings?['tos_enabled'] == true,
    url: settings?['tos_url'] as String?,
    text: settings?['tos_text'] as String?,
  );
}

/// Shows a server's Terms of Service: an allowed web [url] can be confirmed and
/// opened in the external browser; otherwise non-empty inline [text] is shown
/// in an in-app dialog; a no-op when neither is usable.
Future<void> openTos(BuildContext context, {String? url, String? text}) async {
  final tosUrl = url?.trim();
  if (tosUrl != null && tosUrl.isNotEmpty) {
    final result = await openExternalUrl(context, tosUrl);
    if (result != ExternalUrlOpenResult.blocked) return;
  }
  final tosText = text?.trim();
  if (tosText == null || tosText.isEmpty || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Terms of Service'),
      content: SingleChildScrollView(child: Text(tosText)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
