import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hive_ce/hive.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:window_manager/window_manager.dart';

/// Persists and restores the desktop window's last size, position, and
/// maximized state across launches. No-op on web and mobile (where the OS owns
/// window geometry). Backed by the `window-state` Hive box opened in
/// `setupHive`.

const String windowStateBoxName = 'window-state';
const String _key = 'bounds';

/// Default window size used on first launch (matches the Linux runner default).
const Size _defaultSize = Size(1280, 720);

bool get _isDesktop =>
    !UniversalPlatform.isWeb &&
    (UniversalPlatform.isWindows ||
        UniversalPlatform.isLinux ||
        UniversalPlatform.isMacOS);

/// Restores the saved window geometry and starts persisting future changes.
/// Call once during startup, after `setupHive()` (so the box is open) and
/// before `runApp()`.
Future<void> setupDesktopWindow() async {
  if (!_isDesktop) return;

  await windowManager.ensureInitialized();

  final box = Hive.box(windowStateBoxName);
  final raw = box.get(_key);

  Size size = _defaultSize;
  Offset? position;
  bool maximized = false;
  if (raw is Map) {
    final w = (raw['width'] as num?)?.toDouble();
    final h = (raw['height'] as num?)?.toDouble();
    if (w != null && h != null && w > 0 && h > 0) size = Size(w, h);
    final x = (raw['x'] as num?)?.toDouble();
    final y = (raw['y'] as num?)?.toDouble();
    if (x != null && y != null) position = Offset(x, y);
    maximized = raw['maximized'] == true;
  }

  // Center on first launch (no saved position); otherwise restore the exact
  // spot. waitUntilReadyToShow avoids a flash at the default geometry.
  final options = WindowOptions(size: size, center: position == null);
  await windowManager.waitUntilReadyToShow(options, () async {
    if (position != null) await windowManager.setPosition(position);
    if (maximized) await windowManager.maximize();
    await windowManager.show();
    await windowManager.focus();
  });

  windowManager.addListener(_WindowStatePersister(box));
}

/// Saves window geometry on move/resize/(un)maximize, debounced so a drag
/// doesn't write to Hive on every frame. While maximized, only the flag is
/// updated — the last normal bounds are preserved for un-maximize restore.
class _WindowStatePersister extends WindowListener {
  _WindowStatePersister(this._box);

  final Box _box;
  Timer? _debounce;

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _save);
  }

  Future<void> _save() async {
    try {
      final maximized = await windowManager.isMaximized();
      final record = <String, dynamic>{
        ...?(_box.get(_key) as Map?)?.cast<String, dynamic>(),
        'maximized': maximized,
      };
      if (!maximized) {
        final bounds = await windowManager.getBounds();
        record['x'] = bounds.left;
        record['y'] = bounds.top;
        record['width'] = bounds.width;
        record['height'] = bounds.height;
      }
      await _box.put(_key, record);
    } catch (_) {
      // Geometry is best-effort; never let a persistence hiccup surface.
    }
  }

  @override
  void onWindowResized() => _scheduleSave();

  @override
  void onWindowMoved() => _scheduleSave();

  @override
  void onWindowMaximize() => _scheduleSave();

  @override
  void onWindowUnmaximize() => _scheduleSave();
}
