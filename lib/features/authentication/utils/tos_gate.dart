import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/shared/utils/external_url.dart';
import 'package:flutter/material.dart';

/// Whether a server advertises its own Terms of Service, on top of the app's
/// bundled terms. Note the two failure values: a settings read that never came
/// back is *not* [absent], because the server may well require terms we
/// couldn't show (#289).
enum TosAvailability {
  /// The server's settings say it requires acceptance of its own terms.
  advertised,

  /// The server answered, and configures no terms of its own.
  absent,

  /// The settings read was refused (`401`/`403`).
  ///
  /// accordserver serves `GET /settings` to authenticated users only, so this
  /// is the *expected* outcome of every signed-out read — today it is what
  /// happens on the register tab of every instance that exists. It is logged,
  /// but deliberately says nothing to the user: a permanent "couldn't be
  /// loaded" note on the registration screen reads as a half-configured
  /// feature (App Review guideline 2.2, #292) and would show up in the
  /// pre-auth terms screen recording #293 asks for. Please don't "fix" this
  /// back into a visible warning. When the accordserver follow-up in #289
  /// exposes the ToS fields on an unauthenticated endpoint, this case stops
  /// happening on its own.
  refused,

  /// The settings read failed for some other reason — network error, timeout,
  /// `5xx`, malformed body. Genuinely unexpected rather than structural, so
  /// [tosUnavailableNotice] tells the user the server's terms are missing
  /// instead of hiding it.
  unknown,
}

/// Shown in register mode for [TosAvailability.unknown] only — never for
/// [TosAvailability.refused], which is the expected signed-out `401` and stays
/// silent to the user (see the enum for why). Deliberately mild: the app's own
/// terms have already been accepted by this point, so this is supplementary
/// information, not a blocker and not an error.
const String tosUnavailableNotice =
    "This server's own terms couldn't be loaded. You can still register — the "
    "app's Terms of Use and Community Guidelines apply either way.";

/// A server's Terms-of-Service registration gate, read from its public
/// settings: whether acceptance is required, plus the ToS link and/or inline
/// text to show. Shared by the login screen and the Add-a-Server dialog, which
/// each keep the values in their own form state.
typedef TosConfig = ({TosAvailability availability, String? url, String? text});

/// Fetches [server]'s ToS config through [auth]'s public-settings read.
///
/// A failed read never resolves to [TosAvailability.absent] — the gate must not
/// silently vanish. It splits by cause instead: an authentication refusal is
/// [TosAvailability.refused] (expected, logged, invisible), anything else is
/// [TosAvailability.unknown] (surfaced to the user).
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
