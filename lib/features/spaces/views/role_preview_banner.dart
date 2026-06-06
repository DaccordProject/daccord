import 'package:bonfire/features/spaces/controllers/role_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A persistent banner shown while previewing the UI as a role ("imposter"
/// mode), with an exit control. Ports the reference client's
/// `imposter_banner.gd`. Permission-gated UI elsewhere reads the same
/// [rolePreviewControllerProvider], so the app appears as that role would see it
/// until the user exits here.
class RolePreviewBanner extends ConsumerWidget {
  const RolePreviewBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(rolePreviewControllerProvider);
    if (preview == null) return const SizedBox.shrink();

    return Material(
      color: Colors.amber.shade800,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.visibility, size: 16, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Previewing as “${preview.roleName}” — permissions shown are '
                  'this role’s.',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(rolePreviewControllerProvider.notifier).exit(),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                ),
                child: const Text('Exit preview'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
