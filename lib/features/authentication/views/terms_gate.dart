import 'package:bonfire/features/authentication/models/app_terms.dart';
import 'package:bonfire/shared/utils/responsive_dialog.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// The app's own terms gate, shown before the signed-out flow can be used.
///
/// App Store Review Guideline 1.2 requires an EULA to be presented *before* a
/// user registers or signs in; a server's own Terms of Service can't satisfy
/// that (it is optional, per-instance, and only readable once authenticated —
/// see #289), so this gate is unconditional and lives ahead of the credentials
/// form rather than inside it.
class TermsGateView extends StatelessWidget {
  const TermsGateView({super.key, required this.onAccept});

  /// Called once the user agrees. The caller records acceptance and moves on.
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Image.asset('assets/images/icon.png', width: 64, height: 64),
        ),
        const SizedBox(height: 14),
        Text(
          appTermsTitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          appTermsSummary,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.gray),
        ),
        const SizedBox(height: 16),
        const AppTermsBody(),
        const SizedBox(height: 16),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: onAccept,
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: Colors.white,
              textStyle: theme.textTheme.titleSmall,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Agree and continue'),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'You must accept these terms to create an account or sign in.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: colors.gray),
        ),
      ],
    );
  }
}

/// The scrollable terms text, sized to leave the accept control on screen.
///
/// Bounded on purpose: the gate is hosted inside the login screen's scroll
/// view, so an unbounded text block would push the button out of reach on a
/// phone instead of scrolling within itself.
class AppTermsBody extends StatelessWidget {
  const AppTermsBody({super.key, this.maxHeight});

  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final height =
        maxHeight ??
        (MediaQuery.sizeOf(context).height * 0.45).clamp(180.0, 460.0);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: colors.foreground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.darkGray),
      ),
      padding: const EdgeInsets.all(16),
      child: Scrollbar(
        child: SingleChildScrollView(
          primary: false,
          child: SelectableText(
            appTermsBody.trim(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.dirtyWhite,
              height: 1.45,
            ),
          ),
        ),
      ),
    );
  }
}

/// The always-visible "by continuing you agree" line under the auth form's
/// submit button. Shown in both Sign in and Register modes: the gate is what
/// actually blocks the flow, but Apple's reviewer (and the user) should be able
/// to reach the terms from the form itself at any time.
class AppTermsNotice extends StatelessWidget {
  const AppTermsNotice({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    // Wrap, not Row: the title is long enough to overflow a phone-width form
    // beside the lead-in, and it should fall onto its own line instead.
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'By continuing you agree to the',
          style: theme.textTheme.bodySmall?.copyWith(color: colors.gray),
        ),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            appTermsTitle,
            style: theme.textTheme.bodySmall?.copyWith(color: colors.primary),
          ),
        ),
      ],
    );
  }
}

/// Shows the terms as a dialog, for the "Terms of Use" links on the auth form
/// and in settings once they have already been accepted.
Future<void> showAppTermsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: dialogConstraints(context, maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                appTermsTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Flexible(child: const AppTermsBody(maxHeight: 420)),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
