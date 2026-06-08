import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/authentication/views/auth_form.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/views/accord_discovery.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:url_launcher/url_launcher.dart';

/// Server-URL + credentials login against an Accord server. The Daccord
/// replacement for the Discord `LoginScreen`: it drives [accordAuthProvider]
/// (restore-on-launch → sign in / register → optional MFA or forced password
/// change → connect) and, once a live session exists, hands off to the
/// messaging frame.
///
/// [initialMode] selects the Sign in / Register tab on entry; the `/register`
/// route uses it to land directly on registration.
class AccordLoginScreen extends ConsumerStatefulWidget {
  const AccordLoginScreen({super.key, this.initialMode = AuthMode.signIn});

  final AuthMode initialMode;

  @override
  ConsumerState<AccordLoginScreen> createState() => _AccordLoginScreenState();
}

class _AccordLoginScreenState extends ConsumerState<AccordLoginScreen> {
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _mfaController = TextEditingController();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  late AuthMode _mode = widget.initialMode;

  /// A space chosen from discovery while signed out: once the credentials in
  /// this form authenticate, we join it before handing off to the frame.
  String? _pendingJoinSpaceId;

  /// Client-side validation error for the password-change form.
  String? _resetLocalError;

  /// Client-side validation error for the credentials form (e.g. unaccepted ToS
  /// or too-short registration password).
  String? _authLocalError;

  /// Whether any saved accounts exist, gating the "switch account" link.
  bool _hasAccounts = false;

  // Terms-of-Service config, fetched per server when the Register tab is shown.
  bool _tosEnabled = false;
  bool _tosAccepted = false;
  String? _tosUrl;
  String? _tosText;
  String? _tosFetchedServer;

  /// True until the launch-time session restore attempt settles, so we show a
  /// loader instead of flashing the login form for returning users.
  bool _restoring = true;

  @override
  void initState() {
    super.initState();
    final lastServer = Hive.box('accord-session').get('last-server');
    if (lastServer is String) _serverController.text = lastServer;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final notifier = ref.read(accordAuthProvider.notifier);
      final accounts = await notifier.listAccounts();
      if (mounted) setState(() => _hasAccounts = accounts.isNotEmpty);

      // Don't re-restore over a live session (e.g. when arriving here to add
      // another account from the switcher).
      if (ref.read(accordAuthProvider) is! AccordAuthLoggedIn) {
        await notifier.restoreSession();
      }
      if (mounted) setState(() => _restoring = false);

      // Landed straight on the Register tab (via /register): fetch the ToS gate.
      if (_mode == AuthMode.register) _fetchTos();
    });
  }

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    _mfaController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _onModeChanged(AuthMode mode) {
    setState(() {
      _mode = mode;
      _authLocalError = null;
    });
    if (mode == AuthMode.register) _fetchTos();
  }

  Future<void> _fetchTos() async {
    final raw = _serverController.text.trim();
    if (raw.isEmpty) return;
    final server = AccordServer.fromBaseUrl(raw);
    if (_tosFetchedServer == server.baseUrl) return;
    final settings = await ref
        .read(accordAuthProvider.notifier)
        .fetchServerSettings(server);
    if (!mounted) return;
    setState(() {
      _tosFetchedServer = server.baseUrl;
      _tosEnabled = settings?['tos_enabled'] == true;
      _tosUrl = settings?['tos_url'] as String?;
      _tosText = settings?['tos_text'] as String?;
      _tosAccepted = false;
    });
  }

  void _generatePassword() {
    _passwordController.text = generateAuthPassword();
  }

  Future<void> _openTos() async {
    final url = _tosUrl?.trim();
    if (url != null && url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }
    final text = _tosText?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Terms of Service'),
        content: SingleChildScrollView(child: Text(text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Discovery (opened from this screen while signed out) needs auth against
  /// `serverUrl` before joining `spaceId`: pre-fill the form and remember the
  /// space so the next successful login joins it automatically.
  void _onDiscoveryJoinRequiresAuth(String serverUrl, String spaceId) {
    Hive.box('accord-session').put('last-server', serverUrl);
    setState(() {
      _serverController.text = serverUrl;
      _pendingJoinSpaceId = spaceId;
      _mode = AuthMode.signIn;
      _authLocalError = null;
    });
  }

  Future<void> _joinPendingSpace(AccordClient client, String spaceId) async {
    final result = await client.spaces.join(spaceId);
    if (!mounted) return;
    final space = result.data;
    if ((result.ok || result.statusCode == 409) && space is AccordSpace) {
      ref.read(spacesControllerProvider.notifier).upsertSpace(space);
    }
  }

  void _submit() {
    final rawServer = _serverController.text.trim();
    if (rawServer.isEmpty) return;
    Hive.box('accord-session').put('last-server', rawServer);
    final server = AccordServer.fromBaseUrl(rawServer);
    final notifier = ref.read(accordAuthProvider.notifier);

    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) return;

    if (_mode == AuthMode.register) {
      // Usernames are the public login identifier (login looks up by username,
      // not email), so reject email-like input rather than silently accepting
      // a misleading account name. The server enforces this authoritatively too.
      if (username.contains('@')) {
        setState(() => _authLocalError = "Username can't be an email address.");
        return;
      }
      if (password.length < 8) {
        setState(
          () => _authLocalError = 'Password must be at least 8 characters.',
        );
        return;
      }
      if (_tosEnabled && !_tosAccepted) {
        setState(
          () => _authLocalError = 'You must accept the Terms of Service.',
        );
        return;
      }
      setState(() => _authLocalError = null);
      notifier.registerWithCredentials(
        server: server,
        username: username,
        password: password,
        displayName: _displayNameController.text.trim(),
      );
    } else {
      setState(() => _authLocalError = null);
      notifier.loginWithCredentials(
        server: server,
        username: username,
        password: password,
      );
    }
  }

  void _submitGuest() {
    final rawServer = _serverController.text.trim();
    if (rawServer.isEmpty) {
      setState(() => _authLocalError = 'Enter a server URL first.');
      return;
    }
    Hive.box('accord-session').put('last-server', rawServer);
    setState(() => _authLocalError = null);
    ref
        .read(accordAuthProvider.notifier)
        .loginAsGuest(AccordServer.fromBaseUrl(rawServer));
  }

  void _submitMfa() {
    final code = _mfaController.text.trim();
    if (code.isEmpty) return;
    ref.read(accordAuthProvider.notifier).submitMfa(code);
  }

  void _submitPasswordChange() {
    final oldPw = _oldPasswordController.text;
    final newPw = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;
    if (oldPw.isEmpty || newPw.isEmpty) return;
    if (newPw.length < 8) {
      setState(
        () => _resetLocalError = 'New password must be at least 8 characters.',
      );
      return;
    }
    if (newPw != confirm) {
      setState(() => _resetLocalError = 'Passwords do not match.');
      return;
    }
    setState(() => _resetLocalError = null);
    ref
        .read(accordAuthProvider.notifier)
        .submitPasswordChange(oldPassword: oldPw, newPassword: newPw);
  }

  void _navigateToHome() => context.go('/spaces');

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(accordAuthProvider);

    ref.listen(accordAuthProvider, (previous, next) {
      if (next is AccordAuthLoggedIn) {
        final spaceId = _pendingJoinSpaceId;
        _pendingJoinSpaceId = null;
        if (spaceId != null) _joinPendingSpace(next.client, spaceId);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _navigateToHome();
        });
      }
    });

    // Handle landing on the login route while *already* logged in (e.g. tapping
    // "back" out of /admin or /settings, whose router parent is this screen).
    // `ref.listen` only fires on a state *change*, so without this the screen
    // would sit on the "Signing in…" loader forever. Redirect straight home.
    if (state is AccordAuthLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _navigateToHome();
      });
    }

    final Widget body;
    if (_restoring ||
        state is AccordAuthInProgress ||
        state is AccordAuthLoggedIn) {
      body = _Loading(label: _restoring ? 'Reconnecting…' : 'Signing in…');
    } else if (state is AccordAuthMfaRequired) {
      body = _MfaForm(
        controller: _mfaController,
        onSubmit: _submitMfa,
        onCancel: () => ref.read(accordAuthProvider.notifier).logout(),
      );
    } else if (state is AccordAuthPasswordResetRequired) {
      body = _PasswordResetForm(
        oldController: _oldPasswordController,
        newController: _newPasswordController,
        confirmController: _confirmPasswordController,
        onSubmit: _submitPasswordChange,
        onCancel: () => ref.read(accordAuthProvider.notifier).logout(),
        error: _resetLocalError ?? state.error,
      );
    } else {
      body = _AuthForm(
        serverController: _serverController,
        usernameController: _usernameController,
        passwordController: _passwordController,
        displayNameController: _displayNameController,
        mode: _mode,
        hasAccounts: _hasAccounts,
        tosEnabled: _tosEnabled,
        tosAccepted: _tosAccepted,
        onModeChanged: _onModeChanged,
        onSwitchAccount: () => context.go('/switcher'),
        onGeneratePassword: _generatePassword,
        onTosChanged: (v) => setState(() => _tosAccepted = v),
        onTosLinkTap: _openTos,
        onGuest: _submitGuest,
        onDiscover: () => showAccordDiscovery(
          context,
          onJoinRequiresAuth: _onDiscoveryJoinRequiresAuth,
        ),
        onSubmit: _submit,
        error:
            _authLocalError ??
            (state is AccordAuthFailed ? state.message : null),
      );
    }

    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: body,
          ),
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

class _AuthForm extends StatelessWidget {
  const _AuthForm({
    required this.serverController,
    required this.usernameController,
    required this.passwordController,
    required this.displayNameController,
    required this.mode,
    required this.hasAccounts,
    required this.tosEnabled,
    required this.tosAccepted,
    required this.onModeChanged,
    required this.onSwitchAccount,
    required this.onGeneratePassword,
    required this.onTosChanged,
    required this.onTosLinkTap,
    required this.onGuest,
    required this.onDiscover,
    required this.onSubmit,
    this.error,
  });

  final TextEditingController serverController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final TextEditingController displayNameController;
  final AuthMode mode;
  final bool hasAccounts;
  final bool tosEnabled;
  final bool tosAccepted;
  final ValueChanged<AuthMode> onModeChanged;
  final VoidCallback onSwitchAccount;
  final VoidCallback onGeneratePassword;
  final ValueChanged<bool> onTosChanged;
  final VoidCallback onTosLinkTap;
  final VoidCallback onGuest;
  final VoidCallback onDiscover;
  final VoidCallback onSubmit;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final isRegister = mode == AuthMode.register;
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
        const SizedBox(height: 24),
        AuthCredentialsFields(
          mode: mode,
          onModeChanged: onModeChanged,
          serverController: serverController,
          usernameController: usernameController,
          passwordController: passwordController,
          displayNameController: displayNameController,
          tosEnabled: tosEnabled,
          tosAccepted: tosAccepted,
          onTosChanged: onTosChanged,
          onTosLinkTap: onTosLinkTap,
          onGeneratePassword: onGeneratePassword,
          onSubmit: onSubmit,
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(
            error!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium!.copyWith(color: colors.red),
          ),
        ],
        const SizedBox(height: 24),
        _SubmitButton(
          label: isRegister ? 'Register' : 'Log In',
          onPressed: onSubmit,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: Divider(color: colors.darkGray)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('or', style: theme.textTheme.bodySmall),
            ),
            Expanded(child: Divider(color: colors.darkGray)),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onDiscover,
          icon: const Icon(Icons.explore_outlined, size: 18),
          label: const Text('Discover public servers'),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: onGuest,
              child: Text(
                'Browse as guest',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (hasAccounts) ...[
              Text('·', style: theme.textTheme.bodyMedium),
              TextButton(
                onPressed: onSwitchAccount,
                child: Text(
                  'Switch account',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ],
        ),
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
        AuthField(
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

class _PasswordResetForm extends StatelessWidget {
  const _PasswordResetForm({
    required this.oldController,
    required this.newController,
    required this.confirmController,
    required this.onSubmit,
    required this.onCancel,
    this.error,
  });

  final TextEditingController oldController;
  final TextEditingController newController;
  final TextEditingController confirmController;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Change your password',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'The server requires a new password before you can continue',
          textAlign: TextAlign.center,
          style: GoogleFonts.publicSans(
            color: const Color(0xFFC8C8C8),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 32),
        AuthField(
          controller: oldController,
          label: 'Current password',
          obscureText: true,
        ),
        const SizedBox(height: 12),
        AuthField(
          controller: newController,
          label: 'New password',
          obscureText: true,
        ),
        const SizedBox(height: 12),
        AuthField(
          controller: confirmController,
          label: 'Confirm new password',
          obscureText: true,
          onSubmitted: (_) => onSubmit(),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(
            error!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium!.copyWith(
              color: BonfireThemeExtension.of(context).red,
            ),
          ),
        ],
        const SizedBox(height: 24),
        _SubmitButton(label: 'Change Password', onPressed: onSubmit),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onCancel,
          child: Text('Cancel', style: theme.textTheme.bodyMedium),
        ),
      ],
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
          style: Theme.of(
            context,
          ).textTheme.titleSmall!.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}
