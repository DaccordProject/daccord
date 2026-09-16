# livekit_client (Daccord fork)

Local fork of [livekit_client 2.8.0](https://github.com/livekit/client-sdk-flutter)
used for Daccord voice, video, and screen sharing. Upstream docs:
https://docs.livekit.io/reference/client-sdk-flutter/

Fork change (#68): when `kLiveKitSkipNativeRelease` is set (Linux only, see
`lib/main.dart`), native WebRTC resources are not freed on disconnect, because
the prebuilt `libwebrtc.so` heap-corrupts during teardown. The OS reclaims them
at exit. See the `dependency_overrides` comments in the root `pubspec.yaml`.
