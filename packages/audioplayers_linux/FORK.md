# audioplayers_linux (Daccord fork)

Vendored from [audioplayers_linux 4.2.1](https://pub.dev/packages/audioplayers_linux/versions/4.2.1)
and wired in through `dependency_overrides` in the app's `pubspec.yaml`.

One patch, in `linux/audioplayers_linux_plugin.cc`: the `create` method now
catches the exception `AudioPlayer`'s constructor throws when GStreamer can't
build its pipeline (for example, `playbin` is missing without
`gstreamer1.0-plugins-base`) and answers with a `LinuxAudioError` instead of
letting it reach `std::terminate`, which aborted the whole app at startup.

Upstream (4.3.0 and `main`) still creates the player outside any `try`. Drop the
fork once that is fixed.
