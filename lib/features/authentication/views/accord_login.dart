import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

/// Server-URL + credentials login against an Accord server. The Daccord
/// replacement for the Discord `LoginScreen`: it drives [accordAuthProvider]
/// (restore-on-launch → credentials → optional MFA → connect) and, once a live
/// session exists, hands off to the messaging frame.
class AccordLoginScreen extends ConsumerStatefulWidget {
  const AccordLoginScreen({super.key});

  @override
  ConsumerState<AccordLoginScreen> createState() => _AccordLoginScreenState();
}

class _AccordLoginScreenState extends ConsumerState<AccordLoginScreen> {
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _mfaController = TextEditingController();

  /// True until the launch-time session restore attempt settles, so we show a
  /// loader instead of flashing the login form for returning users.
  bool _restoring = true;

  @override
  void initState() {
    super.initState();
    final lastServer = Hive.box('accord-session').get('last-server');
    if (lastServer is String) _serverController.text = lastServer;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(accordAuthProvider.notifier).restoreSession();
      if (mounted) setState(() => _restoring = false);
    });
  }

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _mfaController.dispose();
    super.dispose();
  }

  void _submitCredentials() {
    final rawServer = _serverController.text.trim();
    if (rawServer.isEmpty ||
        _usernameController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      return;
    }
    Hive.box('accord-session').put('last-server', rawServer);
    ref.read(accordAuthProvider.notifier).loginWithCredentials(
          server: AccordServer.fromBaseUrl(rawServer),
          username: _usernameController.text.trim(),
          password: _passwordController.text,
        );
  }

  void _submitMfa() {
    final code = _mfaController.text.trim();
    if (code.isEmpty) return;
    ref.read(accordAuthProvider.notifier).submitMfa(code);
  }

  void _navigateToHome() {
    context.go('/spaces');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(accordAuthProvider);

    ref.listen(accordAuthProvider, (previous, next) {
      if (next is AccordAuthLoggedIn) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _navigateToHome();
        });
      }
    });

    final Widget body;
    if (_restoring ||
        state is AccordAuthInProgress ||
        state is AccordAuthLoggedIn) {
      body = _Loading(
        label: _restoring ? 'Reconnecting…' : 'Signing in…',
      );
    } else if (state is AccordAuthMfaRequired) {
      body = _MfaForm(
        controller: _mfaController,
        onSubmit: _submitMfa,
        onCancel: () => ref.read(accordAuthProvider.notifier).logout(),
      );
    } else {
      body = _CredentialsForm(
        serverController: _serverController,
        usernameController: _usernameController,
        passwordController: _passwordController,
        onSubmit: _submitCredentials,
        error: state is AccordAuthFailed ? state.message : null,
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: body,
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).textTheme.bodyMedium!.color!;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 30),
        LoadingAnimationWidget.fourRotatingDots(color: color, size: 50),
      ],
    );
  }
}

class _CredentialsForm extends StatelessWidget {
  const _CredentialsForm({
    required this.serverController,
    required this.usernameController,
    required this.passwordController,
    required this.onSubmit,
    this.error,
  });

  final TextEditingController serverController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final VoidCallback onSubmit;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Welcome to Daccord',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Connect to your Accord server',
          textAlign: TextAlign.center,
          style: GoogleFonts.publicSans(
            color: const Color(0xFFC8C8C8),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 32),
        _LoginField(
          controller: serverController,
          label: 'Server URL',
          hint: 'https://your.accord.server',
          keyboardType: TextInputType.url,
          autofillHints: const [AutofillHints.url],
        ),
        const SizedBox(height: 12),
        _LoginField(
          controller: usernameController,
          label: 'Username or email',
          autofillHints: const [AutofillHints.username],
        ),
        const SizedBox(height: 12),
        _LoginField(
          controller: passwordController,
          label: 'Password',
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => onSubmit(),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(
            error!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium!
                .copyWith(color: BonfireThemeExtension.of(context).red),
          ),
        ],
        const SizedBox(height: 24),
        _SubmitButton(label: 'Log In', onPressed: onSubmit),
      ],
    );
  }
}

class _MfaForm extends StatelessWidget {
  const _MfaForm({
    required this.controller,
    required this.onSubmit,
    required this.onCancel,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Two-factor authentication',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Enter the code from your authenticator app',
          textAlign: TextAlign.center,
          style: GoogleFonts.publicSans(
            color: const Color(0xFFC8C8C8),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 32),
        _LoginField(
          controller: controller,
          label: '6-digit code',
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          onSubmitted: (_) => onSubmit(),
        ),
        const SizedBox(height: 24),
        _SubmitButton(label: 'Verify', onPressed: onSubmit),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onCancel,
          child: Text('Cancel', style: theme.textTheme.bodyMedium),
        ),
      ],
    );
  }
}

class _LoginField extends StatelessWidget {
  const _LoginField({
    required this.controller,
    required this.label,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.autofillHints,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      onSubmitted: onSubmitted,
      style: Theme.of(context).textTheme.bodyLarge,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: colors.darkGray,
        labelStyle: Theme.of(context).textTheme.bodyMedium,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context)
              .textTheme
              .titleSmall!
              .copyWith(color: Colors.white),
        ),
      ),
    );
  }
}
