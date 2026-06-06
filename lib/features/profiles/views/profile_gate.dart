import 'package:bonfire/features/profiles/controllers/profiles_controller.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the active profile has been unlocked this session. Resets to false on
/// every app (re)start (a fresh [ProviderScope]), so a PIN-locked profile must
/// be unlocked again after launch or after switching into it.
class ProfileUnlocked extends Notifier<bool> {
  @override
  bool build() => false;

  void unlock() => state = true;
}

final profileUnlockedProvider =
    NotifierProvider<ProfileUnlocked, bool>(ProfileUnlocked.new);

/// Gates [child] behind the active profile's PIN. When the active profile has no
/// PIN, or once the correct PIN is entered, [child] is shown.
class ProfileGate extends ConsumerWidget {
  const ProfileGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild when the profile list changes (e.g. PIN added/removed).
    ref.watch(profilesControllerProvider);
    final active = ref.read(profilesControllerProvider.notifier).active;
    final unlocked = ref.watch(profileUnlockedProvider);

    if (active == null || !active.hasPin || unlocked) return child;
    return _PinLockScreen(profileName: active.name);
  }
}

class _PinLockScreen extends ConsumerStatefulWidget {
  const _PinLockScreen({required this.profileName});

  final String profileName;

  @override
  ConsumerState<_PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends ConsumerState<_PinLockScreen> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final notifier = ref.read(profilesControllerProvider.notifier);
    final id = notifier.activeId;
    if (notifier.verifyPin(id, _controller.text)) {
      ref.read(profileUnlockedProvider.notifier).unlock();
    } else {
      setState(() => _error = 'Incorrect PIN');
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Scaffold(
      backgroundColor: colors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 48, color: colors.primary),
                const SizedBox(height: 16),
                Text(
                  widget.profileName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Enter your PIN to unlock this profile',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall!.copyWith(color: colors.gray),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: 'PIN',
                    errorText: _error,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submit,
                    child: const Text('Unlock'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
