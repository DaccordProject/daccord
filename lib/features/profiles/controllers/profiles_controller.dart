import 'package:bonfire/features/profiles/models/device_profile.dart';
import 'package:bonfire/features/profiles/services/profile_store.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'profiles_controller.g.dart';

/// Reactive view over the local device-profile registry. Delegates persistence
/// to [ProfileStore] and re-reads after each mutation so the profiles page and
/// the lock gate update together.
@Riverpod(keepAlive: true)
class ProfilesController extends _$ProfilesController {
  @override
  List<DeviceProfile> build() => ProfileStore.profiles;

  String get activeId => ProfileStore.activeId;
  DeviceProfile? get active => ProfileStore.active;

  void _refresh() => state = ProfileStore.profiles;

  String create(String name, {String? pin}) {
    final id = ProfileStore.create(name, pin: pin);
    _refresh();
    return id;
  }

  void rename(String id, String name) {
    ProfileStore.rename(id, name);
    _refresh();
  }

  Future<void> delete(String id) async {
    await ProfileStore.delete(id);
    _refresh();
  }

  void setPin(String id, String? pin) {
    ProfileStore.setPin(id, pin);
    _refresh();
  }

  bool verifyPin(String id, String pin) => ProfileStore.verifyPin(id, pin);

  /// Makes [id] active by closing/reopening its storage. Callers MUST restart
  /// the app afterwards (the provider tree still points at the old boxes) — see
  /// the profiles page, which calls the app restart immediately after.
  Future<void> switchProfile(String id) async {
    if (id == ProfileStore.activeId) return;
    await ProfileStore.switchTo(id);
    _refresh();
  }
}
