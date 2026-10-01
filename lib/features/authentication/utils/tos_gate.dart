import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/shared/utils/external_url.dart';
import 'package:flutter/material.dart';

/// Whether a server advertises its own Terms of Service, on top of the app's
/// bundled terms. A failed settings read is never [absent]: the server may
/// still require terms we couldn't show.
enum TosAvailability {
  /// The server's settings say it requires acceptance of its own terms.
  advertised,

  /// The server answered, and configures no terms of its own.
  absent,

  /// The settings read was refused (`401`/`403`) — the expected outcome of
  /// every signed-out read while accordserver serves `GET /settings` to
  /// authenticated users only (#289). Logged but deliberately silent: a
  /// permanent "couldn't be loaded" note on the register screen reads as a
  /// half-configured feature (App Review guideline 2.2). Don't turn this back
  /// into a visible warning.
  refused,

  /// Any other failure (network, timeout, `5xx`, malformed body). Unexpected,
  /// so [tosUnavailableNotice] tells the user the server's terms are missing.
  unknown,
}

/// Shown in register mode for [TosAvailability.unknown] only. Deliberately
/// mild: the app's own terms have already been accepted, so this is
/// information, not a blocker.
const String tosUnavailableNotice =
    "This server's own terms couldn't be loaded. You can still register — the "
    "app's Terms of Use and Community Guidelines apply either way.";

/// A server's Terms-of-Service registration gate, read from its public
/// settings: whether acceptance is required, plus the ToS link and/or inline
/// text to show.
typedef TosConfig = ({TosAvailability availability, String? url, String? text});

/// The config before a fetch answers: no gate, so none flashes in the meantime.
const TosConfig tosNotFetched = (
  availability: TosAvailability.absent,
  url: null,
  text: null,
);

/// Fetches [server]'s ToS config through [auth]'s public-settings read. A
/// failed read is [TosAvailability.refused] or [TosAvailability.unknown], never
/// [TosAvailability.absent], so the gate can't silently vanish.
Future<TosConfig> fetchTosConfig(AccordAuth auth, AccordServer server) async {
  final result = await auth.fetchServerSettings(server);
  final settings = result.settings;
  if (settings == null) {
    final refused = result.statusCode == 401 || result.statusCode == 403;
    return (
      availability: refused ? TosAvailability.refused : TosAvailability.unknown,
      url: null,
      text: null,
    );
  }
  return (
    availability: settings['tos_enabled'] == true
        ? TosAvailability.advertised
        : TosAvailability.absent,
    url: settings['tos_url'] as String?,
    text: settings['tos_text'] as String?,
  );
}

/// Shows a server's Terms of Service: an allowed web `url` can be confirmed and
/// opened in the external browser; otherwise non-empty inline `text` is shown
/// in an in-app dialog; a no-op when neither is usable.
Future<void> openTos(BuildContext context, TosConfig tos) async {
  final tosUrl = tos.url?.trim();
  if (tosUrl != null && tosUrl.isNotEmpty) {
    final result = await openExternalUrl(context, tosUrl);
    if (result != ExternalUrlOpenResult.blocked) return;
  }
  final tosText = tos.text?.trim();
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
