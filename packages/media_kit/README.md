# media_kit (Daccord fork)

Local fork of [media_kit 1.1.11](https://github.com/media-kit/media-kit)
(upstream commit 652c49e). Upstream docs: https://github.com/media-kit/media-kit

Fork change: `NativePlayer.dispose` defers closing libmpv's wakeup
`NativeCallable` until after `mpv_terminate_destroy`. Closing it early aborted
the process when a video attachment was disposed (upstream PR #1424).
