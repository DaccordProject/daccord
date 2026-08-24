import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/authentication/utils/credential_validation.dart';
import 'package:bonfire/features/authentication/utils/tos_gate.dart';
import 'package:bonfire/features/authentication/views/auth_form.dart';
import 'package:bonfire/features/authentication/views/password_reset_form.dart';
import 'package:bonfire/features/authentication/views/welcome_view.dart';
import 'package:bonfire/features/profiles/services/profile_store.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/views/accord_discovery.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Server-URL + credentials login against an Accord server. The Daccord
/// replacement for the Discord `LoginScreen`: it drives [accordAuthProvider]
/// (restore-on-launch → sign in / register → optional MFA or forced password
/// change → connect) and, once a live session exists, hands off to the
/// messaging frame.
///
/// [initialMode] selects the Sign in / Register tab on entry; the `/register`
/// route uses it to land directly on registration.
///
/// [startOnCredentials] skips the welcome → browser onboarding and lands
/// directly on the connect-by-URL credentials form. The `/login` and `/register`
/// routes set it so deep links and "add another account" go straight to the
/// form, while the default `/` route opens onboarding.
class AccordLoginScreen extends ConsumerStatefulWidget {
  const AccordLoginScreen({
    super.key,
    this.initialMode = AuthMode.signIn,
    this.startOnCredentials = false,
  });

  final AuthMode initialMode;
  final bool startOnCredentials;

  @override
  ConsumerState<AccordLoginScreen> createState() => _AccordLoginScreenState();
}

/// The signed-out sub-flow: branded onboarding → public server browser → the
/// credentials form for the chosen instance.
enum _LoggedOutView { welcome, browse, credentials }

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

  /// Which signed-out sub-view is showing. Defaults to onboarding unless the
  /// route asked to land on the credentials form.
  late _LoggedOutView _view = widget.startOnCredentials
      ? _LoggedOutView.credentials
      : _LoggedOutView.welcome;

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
    final lastServer = ProfileStore.sessionBox.get('last-server');
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

  AccordServer? _serverFromInput(String raw) {
    try {
      return AccordServer.fromBaseUrl(raw);
    } on FormatException catch (error) {
      if (mounted) setState(() => _authLocalError = error.message);
      return null;
    }
  }

  Future<void> _fetchTos() async {
    final raw = _serverController.text.trim();
    if (raw.isEmpty) return;
    final server = _serverFromInput(raw);
    if (server == null) return;
    if (_tosFetchedServer == server.baseUrl) return;
    final tos = await fetchTosConfig(
      ref.read(accordAuthProvider.notifier),
      server,
    );
    if (!mounted) return;
    setState(() {
      _tosFetchedServer = server.baseUrl;
      _tosEnabled = tos.enabled;
      _tosUrl = tos.url;
      _tosText = tos.text;
      _tosAccepted = false;
    });
  }

  void _generatePassword() {
    _passwordController.text = generateAuthPassword();
  }

  Future<void> _openTos() => openTos(context, url: _tosUrl, text: _tosText);

  /// Discovery (the embedded browser while signed out) needs auth against
  /// `serverUrl` before joining `spaceId`: switch to the credentials form,
  /// pre-fill it, and remember the space so the next successful login joins it.
  void _onDiscoveryJoinRequiresAuth(String serverUrl, String spaceId) {
    ProfileStore.sessionBox.put('last-server', serverUrl);
    setState(() {
      _serverController.text = serverUrl;
      _pendingJoinSpaceId = spaceId;
      _mode = AuthMode.signIn;
      _authLocalError = null;
      _view = _LoggedOutView.credentials;
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
    final server = _serverFromInput(rawServer);
    if (server == null) return;
    ProfileStore.sessionBox.put('last-server', rawServer);
    final notifier = ref.read(accordAuthProvider.notifier);

    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) return;

    if (_mode == AuthMode.register) {
      final validationError = validateRegistrationCredentials(
        username: username,
        password: password,
        tosRequired: _tosEnabled,
        tosAccepted: _tosAccepted,
      );
      if (validationError != null) {
        setState(() => _authLocalError = validationError);
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

  void _submitMfa() {
    final code = _mfaController.text.trim();
    if (code.isEmpty) return;
    ref.read(accordAuthProvider.notifier).submitMfa(code);
  }

  void _submitPasswordChange() {
    final oldPw = _oldPasswordController.text;
    final newPw = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;
    final validationError = validatePasswordChangeCredentials(
      oldPassword: oldPw,
      newPassword: newPw,
      confirmation: confirm,
    );
    if (validationError != null) {
      setState(() => _resetLocalError = validationError);
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

    // Covers a login that completes *while this screen is showing* — a state
    // change doesn't re-run router redirects. Landing on a sign-in route while
    // *already* logged in never reaches build: the router redirects it straight
    // home (see `redirectLoggedInToHome` in `lib/router/controller.dart`), and
    // the signed-in screens are siblings of these routes, so this screen is not
    // mounted underneath them.
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

    // Loading / MFA / forced-password-change: simple centered forms with no
    // onboarding chrome.
    if (_restoring ||
        state is AccordAuthInProgress ||
        state is AccordAuthLoggedIn) {
      return _centered(
        _Loading(label: _restoring ? 'Reconnecting…' : 'Signing in…'),
      );
    }
    if (state is AccordAuthMfaRequired) {
      return _centered(
        _MfaForm(
          controller: _mfaController,
          onSubmit: _submitMfa,
          onCancel: () => ref.read(accordAuthProvider.notifier).logout(),
        ),
      );
    }
    if (state is AccordAuthPasswordResetRequired) {
      return _centered(
        PasswordResetForm(
          oldController: _oldPasswordController,
          newController: _newPasswordController,
          confirmController: _confirmPasswordController,
          onSubmit: _submitPasswordChange,
          onCancel: () => ref.read(accordAuthProvider.notifier).logout(),
          error: _resetLocalError ?? state.error,
        ),
      );
    }

    // Signed out: walk welcome → browse → credentials. Intercept system back to
    // step through the sub-flow rather than leaving the screen, except at the
    // flow's entry view.
    final Widget signedOut = switch (_view) {
      _LoggedOutView.welcome => _centered(
        WelcomeView(
          onBrowse: () => setState(() => _view = _LoggedOutView.browse),
          onManualConnect: () =>
              setState(() => _view = _LoggedOutView.credentials),
          onSwitchAccount: _hasAccounts
              ? () => context.push('/switcher')
              : null,
        ),
        maxWidth: 480,
      ),
      _LoggedOutView.browse => _BrowseView(
        onBack: _goBack,
        onManualConnect: () =>
            setState(() => _view = _LoggedOutView.credentials),
        onJoinRequiresAuth: _onDiscoveryJoinRequiresAuth,
      ),
      _LoggedOutView.credentials => _centered(
        _AuthForm(
          serverController: _serverController,
          usernameController: _usernameController,
          passwordController: _passwordController,
          displayNameController: _displayNameController,
          mode: _mode,
          hasAccounts: _hasAccounts,
          tosEnabled: _tosEnabled,
          tosAccepted: _tosAccepted,
          onBack: _atFlowRoot ? null : _goBack,
          onModeChanged: _onModeChanged,
          onSwitchAccount: () => context.push('/switcher'),
          onGeneratePassword: _generatePassword,
          onTosChanged: (v) => setState(() => _tosAccepted = v),
          onTosLinkTap: _openTos,
          onDiscover: () => setState(() => _view = _LoggedOutView.browse),
          onSubmit: _submit,
          error:
              _authLocalError ??
              (state is AccordAuthFailed ? state.message : null),
        ),
      ),
    };

    return PopScope(
      canPop: _atFlowRoot,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: signedOut,
    );
  }

  Widget _centered(Widget child, {double maxWidth = 420}) {
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: child,
          ),
        ),
      ),
    );
  }

  /// The signed-out view from which a back gesture should leave the screen
  /// rather than step back through the onboarding sub-flow.
  bool get _atFlowRoot =>
      _view == _LoggedOutView.welcome ||
      (widget.startOnCredentials && _view == _LoggedOutView.credentials);

  void _goBack() {
    setState(() {
      if (_view == _LoggedOutView.browse) {
        _view = widget.startOnCredentials
            ? _LoggedOutView.credentials
            : _LoggedOutView.welcome;
      } else if (_view == _LoggedOutView.credentials) {
        _view = _pendingJoinSpaceId != null
            ? _LoggedOutView.browse
            : _LoggedOutView.welcome;
        _pendingJoinSpaceId = null;
        _authLocalError = null;
      }
    });
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
        SizedBox(
          width: 50,
          height: 50,
          child: CircularProgressIndicator(color: color),
        ),
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
    required this.onDiscover,
    required this.onSubmit,
    this.onBack,
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
  final VoidCallback? onBack;
  final ValueChanged<AuthMode> onModeChanged;
  final VoidCallback onSwitchAccount;
  final VoidCallback onGeneratePassword;
  final ValueChanged<bool> onTosChanged;
  final VoidCallback onTosLinkTap;
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
        if (onBack != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back'),
            ),
          ),
        Text(
          'Welcome to Daccord',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Connect to your Accord server',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFC8C8C8),
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
        if (hasAccounts)
          TextButton(
            onPressed: onSwitchAccount,
            child: Text('Switch account', style: theme.textTheme.bodyMedium),
          ),
      ],
    );
  }
}

/// The signed-out server browser: a back affordance + the shared public-space
/// directory ([AccordDiscoveryBody]) shown full-screen, with a manual
/// connect-by-URL escape hatch. Joining a listing routes auth back through the
/// hosting login screen via [onJoinRequiresAuth].
class _BrowseView extends StatelessWidget {
  const _BrowseView({
    required this.onBack,
    required this.onManualConnect,
    required this.onJoinRequiresAuth,
  });

  final VoidCallback onBack;
  final VoidCallback onManualConnect;
  final void Function(String serverUrl, String spaceId) onJoinRequiresAuth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back, size: 20),
                  ),
                  Icon(Icons.explore, size: 20, color: colors.dirtyWhite),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Discover Servers',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AccordDiscoveryBody(
                onJoinRequiresAuth: onJoinRequiresAuth,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: TextButton.icon(
                onPressed: onManualConnect,
                icon: const Icon(Icons.link, size: 18),
                label: const Text('Connect to a server by URL'),
              ),
            ),
          ],
        ),
      ),
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
          style: const TextStyle(
            color: Color(0xFFC8C8C8),
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
