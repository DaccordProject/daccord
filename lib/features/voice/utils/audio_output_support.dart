/// Which platforms can actually honour an explicit speaker/output-device
/// choice, so the Voice & Video page only offers the control where it does
/// something.
library;

import 'package:flutter/foundation.dart';

/// Forces [canPickAudioOutputDevice] in tests, which cannot pretend to run on
/// another platform. Null in production. Mirrors `debugAppStoreBuild`.
@visibleForTesting
bool? debugCanPickAudioOutputDevice;

/// Whether this platform supports choosing the audio output device.
///
/// The output-device picker is backed by `rtc.Helper.selectAudioOutput`
/// (`VoiceSession.setAudioOutputDevice`), and what that call *is* differs by
/// platform:
///
/// * **Desktop** — a real device switch (`RTCAudioDeviceModule.setOutputDevice`
///   on macOS, the equivalent on Windows/Linux). LiveKit's own
///   `Hardware.selectAudioOutput` is desktop-only for exactly this reason.
/// * **Android** — also real: enumeration returns `AudioSwitchManager` type
///   names and `selectAudioOutput` takes the same names back, so earpiece /
///   speaker / wired / Bluetooth all round-trip.
/// * **iOS** — neither. Enumeration only ever returns the route already in use
///   (plus a synthetic "Speaker" entry), and the write degrades to
///   `AVAudioSession.overrideOutputAudioPort`, which understands nothing but
///   that one literal `"Speaker"` id. So the dropdown could never offer a
///   device you were not already on, and picking "System default" wrote
///   nothing at all — a control that looked functional and did nothing (#306).
///   iOS owns output routing itself (Control Centre, the AirPlay picker, plugging
///   in a headset), so there is no capability to expose here.
/// * **Web** — `setSinkId` is not wired through this path at all.
bool get canPickAudioOutputDevice =>
    debugCanPickAudioOutputDevice ??
    (!kIsWeb && defaultTargetPlatform != TargetPlatform.iOS);
