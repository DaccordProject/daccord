// bonfire fork (#68): global toggle to skip ALL native WebRTC resource frees.
//
// On Linux the prebuilt libwebrtc.so heap-corrupts when MediaStreamTrack /
// MediaStream / RTCPeerConnection are freed during a (server-forced) disconnect:
// the PulseAudio recording thread races the audio-source free
// (RTCAudioSourceImpl::CaptureFrame use-after-free) and the PeerConnection dtor
// overflows the heap ("corrupted size vs. prev_size"). The race lives entirely
// inside the prebuilt lib and exposes no control surface to app code.
//
// When [kLiveKitSkipNativeRelease] is true, livekit_client skips
// MediaStreamTrack.stop()/dispose(), MediaStream.dispose() and
// RTCPeerConnection.close()/dispose(). Those native objects then leak and are
// reclaimed by the OS at process exit — a bounded per-session leak that is
// strictly preferable to a hard crash on every channel switch/leave.
//
// Off by default so non-Linux platforms keep livekit's normal teardown. Bonfire
// flips it on at startup (Linux only).
bool kLiveKitSkipNativeRelease = false;
