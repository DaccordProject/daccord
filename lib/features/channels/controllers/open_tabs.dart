import 'package:bonfire/features/channels/models/open_tab.dart';
import 'package:collection/collection.dart';
import 'package:hive_ce/hive.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'open_tabs.g.dart';

/// The strip of open channel tabs and which one is active.
class OpenTabsState {
  const OpenTabsState({this.tabs = const [], this.activeKey});

  final List<OpenTab> tabs;

  /// The active tab's [OpenTab.key], or null when nothing is open.
  final String? activeKey;

  OpenTab? get activeTab => tabs.firstWhereOrNull((t) => t.key == activeKey);

  OpenTabsState copyWith({List<OpenTab>? tabs, String? activeKey}) =>
      OpenTabsState(
        tabs: tabs ?? this.tabs,
        activeKey: activeKey ?? this.activeKey,
      );
}

/// Owns the open-channel tab strip (the reference client's `main_window_tabs`).
///
/// Selecting a channel [open]s a tab (or switches to it if already open);
/// closing/reordering mirror the reference's context-menu actions. The whole
/// strip is persisted to the `accord-settings` Hive box (a separate key from
/// [AccordSettings]) so open tabs survive a restart.
@Riverpod(keepAlive: true)
class OpenTabsController extends _$OpenTabsController {
  static const _boxName = 'accord-settings';
  static const _key = 'open-tabs';

  @override
  OpenTabsState build() {
    final raw = Hive.box(_boxName).get(_key);
    if (raw is! Map) return const OpenTabsState();
    final tabs = [
      for (final t in (raw['tabs'] as List? ?? const []))
        if (t is Map) OpenTab.fromJson(t),
    ];
    final activeKey = raw['activeKey'] as String?;
    final active = tabs.any((t) => t.key == activeKey) ? activeKey : null;
    return OpenTabsState(tabs: tabs, activeKey: active);
  }

  void _commit(OpenTabsState next) {
    state = next;
    Hive.box(_boxName).put(_key, {
      'tabs': [for (final t in next.tabs) t.toJson()],
      'activeKey': next.activeKey,
    });
  }

  /// Opens [tab] (or switches to it when already open), making it active. When a
  /// tab with the same identity exists its [OpenTab.name] is refreshed.
  void open(OpenTab tab) {
    final i = state.tabs.indexWhere((t) => t.key == tab.key);
    if (i >= 0) {
      final tabs = [...state.tabs];
      if (tabs[i].name != tab.name) tabs[i] = tabs[i].copyWith(name: tab.name);
      _commit(OpenTabsState(tabs: tabs, activeKey: tab.key));
      return;
    }
    _commit(OpenTabsState(tabs: [...state.tabs, tab], activeKey: tab.key));
  }

  /// Makes the tab identified by [key] active (no-op when it isn't open).
  void activate(String key) {
    if (key == state.activeKey) return;
    if (!state.tabs.any((t) => t.key == key)) return;
    _commit(state.copyWith(activeKey: key));
  }

  /// Refreshes a tab's display name from the live channel (no-op when absent or
  /// unchanged).
  void updateName(String key, String name) {
    final i = state.tabs.indexWhere((t) => t.key == key);
    if (i < 0 || state.tabs[i].name == name) return;
    final tabs = [...state.tabs]..[i] = state.tabs[i].copyWith(name: name);
    _commit(state.copyWith(tabs: tabs));
  }

  /// Closes the tab [key]. When it was active, selects the neighbour that slides
  /// into its slot (clamped), matching the reference's close behaviour.
  void close(String key) {
    final i = state.tabs.indexWhere((t) => t.key == key);
    if (i < 0) return;
    final tabs = [...state.tabs]..removeAt(i);
    var activeKey = state.activeKey;
    if (key == activeKey) {
      activeKey = tabs.isEmpty ? null : tabs[i.clamp(0, tabs.length - 1)].key;
    }
    _commit(OpenTabsState(tabs: tabs, activeKey: activeKey));
  }

  /// Closes every tab except [key], which becomes active.
  void closeOthers(String key) {
    final keep = state.tabs.firstWhereOrNull((t) => t.key == key);
    if (keep == null || state.tabs.length <= 1) return;
    _commit(OpenTabsState(tabs: [keep], activeKey: keep.key));
  }

  /// Closes every tab to the right of [key]; [key] becomes active.
  void closeToRight(String key) {
    final i = state.tabs.indexWhere((t) => t.key == key);
    if (i < 0 || i >= state.tabs.length - 1) return;
    _commit(OpenTabsState(
      tabs: state.tabs.sublist(0, i + 1),
      activeKey: state.tabs[i].key,
    ));
  }

  void reorder(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final tabs = [...state.tabs];
    if (oldIndex < 0 || oldIndex >= tabs.length) return;
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    target = target.clamp(0, tabs.length - 1);
    final moved = tabs.removeAt(oldIndex);
    tabs.insert(target, moved);
    _commit(state.copyWith(tabs: tabs));
  }

  /// Removes all tabs belonging to a disconnected/removed server.
  void removeForServer(String serverKey) {
    if (!state.tabs.any((t) => t.serverKey == serverKey)) return;
    final tabs = state.tabs.where((t) => t.serverKey != serverKey).toList();
    final activeKey =
        tabs.any((t) => t.key == state.activeKey) ? state.activeKey : null;
    _commit(OpenTabsState(tabs: tabs, activeKey: activeKey));
  }

  /// Drops tabs whose owning server isn't in [serverKeys]. Used on session
  /// restore to prune tabs left behind by accounts that have since been logged
  /// out (otherwise they'd linger in the strip as stale duplicates).
  void retainServers(Set<String> serverKeys) {
    if (state.tabs.every((t) => serverKeys.contains(t.serverKey))) return;
    final tabs =
        state.tabs.where((t) => serverKeys.contains(t.serverKey)).toList();
    final activeKey =
        tabs.any((t) => t.key == state.activeKey) ? state.activeKey : null;
    _commit(OpenTabsState(tabs: tabs, activeKey: activeKey));
  }

  void clear() {
    if (state.tabs.isEmpty && state.activeKey == null) return;
    _commit(const OpenTabsState());
  }
}
