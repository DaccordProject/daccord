import 'dart:async';

import 'package:bonfire/features/voice/utils/afk_logic.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Watches for user inactivity while connected to voice and flips an
/// [AfkTracker] between active and AFK.
///
/// Activity is sampled from four sources, none of which require a hook in
/// `main.dart` or a wrapper widget:
///
/// * every pointer event, via `GestureBinding.pointerRouter`'s global route;
/// * every key event, via a passthrough `HardwareKeyboard` handler;
/// * the app returning to the foreground ([AppLifecycleListener]);
/// * the local microphone picking up speech, polled via [micActive].
///
/// Because pointer/key events only reach the app while its window has focus,
/// "window unfocused for the timeout" and "no input for the timeout" both fall
/// out of the same idle clock — which is exactly the two triggers the feature
/// asks for.
class AfkMonitor {
  AfkMonitor({DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    _tracker = AfkTracker(now: _clock());
  }

  final DateTime Function() _clock;
  late final AfkTracker _tracker;

  /// Called with the new value whenever the AFK flag flips.
  ValueChanged<bool>? onAfkChanged;

  /// Whether the local mic is currently registering input. Polled on every
  /// evaluation so talking (with no keyboard/mouse use) keeps you active.
  bool Function()? micActive;

  Timer? _timer;
  Duration? _timerInterval;
  AppLifecycleListener? _lifecycle;
  bool _hooked = false;
  bool _connected = false;
  Duration? _timeout;

  /// Throttles the (very hot) pointer route: re-stamping the idle clock more
  /// than once a second buys nothing and costs a `DateTime.now()` per event.
  DateTime? _lastStamp;

  bool get isAfk => _tracker.isAfk;

  /// Point the monitor at the current voice/settings state. Safe to call on
  /// every change; hooks and the poll timer are (de)installed as needed.
  void update({required bool connected, required Duration? timeout}) {
    _connected = connected;
    _timeout = timeout;
    final eligible = connected && timeout != null && timeout > Duration.zero;
    if (eligible) {
      _hook();
      _schedule(timeout);
    } else {
      _unhook();
    }
    _evaluate();
  }

  /// Records explicit user activity (a voice control tapped, a channel joined).
  void markActivity() {
    if (_tracker.markActivity(_clock())) onAfkChanged?.call(false);
  }

  void dispose() {
    _unhook();
    onAfkChanged = null;
    micActive = null;
  }

  void _schedule(Duration timeout) {
    final interval = afkPollInterval(timeout);
    if (_timer != null && _timerInterval == interval) return;
    _timer?.cancel();
    _timerInterval = interval;
    _timer = Timer.periodic(interval, (_) => _evaluate());
  }

  void _hook() {
    if (_hooked) return;
    _hooked = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    HardwareKeyboard.instance.addHandler(_onKey);
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.resumed) markActivity();
      },
    );
  }

  void _unhook() {
    _timer?.cancel();
    _timer = null;
    _timerInterval = null;
    if (!_hooked) return;
    _hooked = false;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _lifecycle?.dispose();
    _lifecycle = null;
  }

  void _onPointer(PointerEvent event) => _stamp();

  /// Never consumes the key — this is an observer, not a shortcut handler.
  bool _onKey(KeyEvent event) {
    _stamp();
    return false;
  }

  void _stamp() {
    final now = _clock();
    final last = _lastStamp;
    if (last != null && now.difference(last) < const Duration(seconds: 1)) {
      return;
    }
    _lastStamp = now;
    if (_tracker.markActivity(now)) onAfkChanged?.call(false);
  }

  void _evaluate() {
    final now = _clock();
    if (_connected && (micActive?.call() ?? false)) {
      if (_tracker.markActivity(now)) onAfkChanged?.call(false);
      return;
    }
    if (_tracker.tick(now: now, connected: _connected, timeout: _timeout)) {
      onAfkChanged?.call(_tracker.isAfk);
    }
  }
}
