import 'package:bonfire/features/authentication/models/app_terms.dart';
import 'package:hive_ce/hive.dart';

/// Device-global record of the user having accepted [appTermsBody].
///
/// Stored in the `auth` box rather than a profile box: the terms are the app's,
/// not an account's, so switching device profiles or signing out must not
/// re-prompt — while a new terms version must.
const String _termsBoxName = 'auth';
const String _termsVersionKey = 'accepted-app-terms-version';

/// Whether the current [appTermsVersion] has been accepted on this device.
///
/// False when the box isn't open (very early startup, or a test that skipped
/// Hive) — failing closed shows the gate rather than silently skipping it.
bool hasAcceptedAppTerms() {
  if (!Hive.isBoxOpen(_termsBoxName)) return false;
  final stored = Hive.box(_termsBoxName).get(_termsVersionKey);
  final accepted = stored is int ? stored : int.tryParse('$stored');
  return accepted != null && accepted >= appTermsVersion;
}

/// Records acceptance of the current [appTermsVersion].
Future<void> recordAppTermsAcceptance() async {
  if (!Hive.isBoxOpen(_termsBoxName)) return;
  await Hive.box(_termsBoxName).put(_termsVersionKey, appTermsVersion);
}

/// Clears the record, so the gate shows again. Used by tests.
Future<void> clearAppTermsAcceptance() async {
  if (!Hive.isBoxOpen(_termsBoxName)) return;
  await Hive.box(_termsBoxName).delete(_termsVersionKey);
}
