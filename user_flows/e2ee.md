# End-to-End Encryption (E2EE)

## Overview

End-to-end encryption ensures that voice/video media streams are encrypted at the sender and only decrypted at the intended recipients — the LiveKit server (SFU) relays opaque ciphertext and cannot read the media. The godot-livekit GDExtension has E2EE classes compiled behind a `LIVEKIT_E2EE_SUPPORTED` build flag, but the current release binaries are **not** built with E2EE enabled, and daccord does not wire the E2EE API into its voice pipeline. Text messages are not covered by this flow — they travel over REST/WebSocket with transport-layer TLS only.

## User Steps

_None of these steps are implemented yet. This describes the target experience._

1. User joins a voice channel
2. Server returns LiveKit credentials (URL + token) via `POST /channels/{id}/voice/join`
3. Client creates a `LiveKitRoom` and passes `LiveKitE2eeOptions` with a shared key in the `connect_to_room()` options dictionary
4. All local audio/video tracks are encrypted by `LiveKitFrameCryptor` before leaving the client
5. Remote tracks are decrypted on receipt; the lock icon in the voice UI indicates encryption is active
6. If a participant joins without the correct key, their audio/video is silent/blank and their encryption status shows as unencrypted
7. User can view per-participant encryption status via the voice panel

## Signal Flow

```
                         daccord (GDScript)                                godot-livekit (C++)
                              |                                                  |
LiveKitAdapter                |                                                  |
  .connect_to_room(url,token) |                                                  |
     options = {              |                                                  |
       "e2ee": e2ee_opts      |  -- connect_to_room(url, token, options) ------> |
     }                        |                                                  |
                              |                                        LiveKitRoom._connect()
                              |                                          room_options.encryption = e2ee_opts.to_native()
                              |                                          livekit::Room::connect(url, token, opts)
                              |                                                  |
                              |                                        (WebRTC + E2EE frame transform)
                              |                                                  |
                              |  <-- e2ee_state_changed(participant, state) ---- |
                              |  <-- participant_encryption_status_changed() --- |
                              |                                                  |
LiveKitAdapter                |                                                  |
  _on_e2ee_state_changed()    |                                                  |
     -> e2ee_status_changed   |                                                  |
        signal                |                                                  |
                              |                                                  |
ClientVoice                   |                                                  |
  .on_e2ee_status_changed()   |                                                  |
     -> AppState              |                                                  |
        .e2ee_status_changed  |                                                  |
```

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/livekit_adapter.gd` | GDScript adapter wrapping `LiveKitRoom` — would pass `LiveKitE2eeOptions` in the `options` dict and handle E2EE signals |
| `scripts/autoload/client_voice.gd` | Voice channel join/leave — would need to construct E2EE options and propagate encryption status to AppState |
| `scripts/autoload/config_voice.gd` | Voice config persistence — would store E2EE preference (enabled/disabled) |
| `scripts/autoload/app_state.gd` | Signal bus — would need new signals for E2EE state changes |
| `addons/accordkit/models/voice_server_update.gd` | `AccordVoiceServerUpdate` model — could carry an E2EE shared key or key exchange payload from the server |
| `addons/accordkit/models/voice_state.gd` | `AccordVoiceState` model — could carry per-user encryption status |

### External Repository (godot-livekit)

| File | Role |
|------|------|
| `src/livekit_e2ee.h` | Declares `LiveKitE2eeOptions`, `LiveKitKeyProvider`, `LiveKitFrameCryptor`, `LiveKitE2eeManager` |
| `src/livekit_e2ee.cpp` | Implements E2EE classes — shared/per-participant key management, ratcheting, frame cryptor enable/disable |
| `src/livekit_room.h` | `LiveKitRoom` — holds `LiveKitE2eeManager` behind `#ifdef LIVEKIT_E2EE_SUPPORTED` (line 94), exposes `get_e2ee_manager()` (line 122) |
| `src/livekit_room.cpp` | Parses `e2ee` option from connect dictionary (line 162), initializes E2EE manager after connect (line 229), emits `e2ee_state_changed` and `participant_encryption_status_changed` signals (lines 723-743) |
| `src/register_types.cpp` | Conditionally registers E2EE classes with ClassDB (lines 57-62) |
| `SConstruct` | E2EE opt-in: `e2ee=yes` build arg sets `LIVEKIT_E2EE_SUPPORTED` define (lines 121-123), appends `livekit_e2ee.cpp` to sources (lines 137-138) |
| `test/unit/test_e2ee.gd` | 11 tests for E2EE classes — options defaults, key roundtrip, frame cryptor, manager unbound behavior |
| `test/unit/test_platform.gd` | Platform test that checks whether E2EE classes are registered (informational, lines 37-59) |

## Implementation Details

### Current Transport Security

All daccord traffic already uses transport encryption:

- **REST API**: HTTPS by default. The Add Server dialog (`add_server_dialog.gd`, line 66) prepends `https://` to URLs. If HTTPS fails, it falls back to HTTP (line 214) — this is a security concern but separate from E2EE.
- **WebSocket gateway**: Uses `wss://` for TLS-protected WebSocket connections.
- **LiveKit WebRTC**: DTLS-SRTP is mandatory in WebRTC, so media is always encrypted in transit between client and the LiveKit SFU. However, the SFU can decrypt and re-encrypt the media — E2EE adds a second layer that the SFU cannot read.

### godot-livekit E2EE Classes (Conditional Compile)

E2EE is compiled only when building with `scons e2ee=yes` (`SConstruct`, line 121). All E2EE code is wrapped in `#ifdef LIVEKIT_E2EE_SUPPORTED`. The current release binaries are **not** built with this flag.

**LiveKitE2eeOptions** (`livekit_e2ee.h`, line 14):
- `encryption_type`: `ENCRYPTION_NONE (0)`, `ENCRYPTION_GCM (1)`, `ENCRYPTION_CUSTOM (2)` — default is GCM
- `shared_key`: `PackedByteArray` — the symmetric key all participants must share
- `ratchet_salt`: `PackedByteArray` — salt for the key derivation ratchet (default from `livekit::kDefaultRatchetSalt`)
- `ratchet_window_size`: `int` — how many ratchet steps to tolerate (default 16)
- `failure_tolerance`: `int` — how many decryption failures before giving up (default -1, unlimited)
- `to_native()`: converts to `livekit::E2EEOptions` for the C++ SDK (line 84)

**LiveKitKeyProvider** (`livekit_e2ee.h`, line 56):
- `set_shared_key(key, key_index)` / `get_shared_key(key_index)` — room-wide shared key at a given index
- `ratchet_shared_key(key_index)` — advances the shared key via ratchet, returns the new key
- `set_key(participant_identity, key, key_index)` / `get_key(...)` — per-participant keys
- `ratchet_key(participant_identity, key_index)` — per-participant ratchet
- All methods are no-ops with error prints if the provider is unbound (`livekit_e2ee.cpp`, lines 126-191)

**LiveKitFrameCryptor** (`livekit_e2ee.h`, line 80):
- `participant_identity`: read-only, set from bound native object
- `enabled`: enable/disable encryption for a specific participant's tracks
- `key_index`: which key slot to use for this participant's encryption

**LiveKitE2eeManager** (`livekit_e2ee.h`, line 108):
- `enabled`: master enable/disable toggle for the room's E2EE
- `key_provider`: returns the `LiveKitKeyProvider` for the room (lazy-initialized, line 304 of `livekit_e2ee.cpp`)
- `frame_cryptors`: returns an `Array` of `LiveKitFrameCryptor` objects, one per participant's track

### Room Connection with E2EE

When `connect_to_room()` is called, `livekit_room.cpp` checks for an `"e2ee"` key in the options dictionary (line 162):

```cpp
if (options.has("e2ee")) {
    Ref<LiveKitE2eeOptions> e2ee_opts = options["e2ee"];
    if (e2ee_opts.is_valid()) {
        room_options.encryption = e2ee_opts->to_native();
    }
}
```

After a successful connection, the E2EE manager is initialized (line 229):

```cpp
livekit::E2EEManager *mgr = room->e2eeManager();
if (mgr) {
    e2ee_manager_.instantiate();
    e2ee_manager_->bind_manager(mgr);
}
```

### Room Signals for E2EE

Two signals are registered when E2EE is supported (`livekit_room.cpp`, lines 109-116):

- `e2ee_state_changed(participant: LiveKitParticipant, state: int)` — fired when a participant's E2EE state changes (e.g., from encrypting to decrypted, or failure)
- `participant_encryption_status_changed(participant: LiveKitParticipant, is_encrypted: bool)` — fired when a participant starts or stops using encryption

### Key Ratcheting

The key ratchet provides forward secrecy for voice sessions. When `ratchet_shared_key(key_index)` or `ratchet_key(identity, key_index)` is called, the key advances to a new derived value. The `ratchet_window_size` (default 16) controls how many old keys are kept so that slightly-out-of-sync participants can still decrypt recent frames.

### What daccord Would Need to Wire

1. **Build godot-livekit with E2EE**: `scons platform=linux e2ee=yes` — the current release binaries do not include E2EE
2. **Key exchange**: Either the server provides a shared key in `AccordVoiceServerUpdate`, or clients use an out-of-band key agreement (e.g., a room passphrase entered by the channel creator)
3. **LiveKitAdapter changes**: Pass `LiveKitE2eeOptions` in the options dict when calling `_room.connect_to_room()`, connect the two E2EE signals
4. **Config persistence**: Add `Config.voice.get_e2ee_enabled()` / `set_e2ee_enabled()` to `config_voice.gd`
5. **AppState signals**: Add `e2ee_status_changed(user_id: String, is_encrypted: bool)` signal
6. **UI indicators**: Lock icon on voice channel items, per-participant encryption badge in the member list / voice panel
7. **Error handling**: Handle the case where a participant joins without E2EE (their frames are unreadable) — show a warning in the UI

## Implementation Status

- [x] E2EE C++ classes written and conditionally compiled in godot-livekit (`LiveKitE2eeOptions`, `LiveKitKeyProvider`, `LiveKitFrameCryptor`, `LiveKitE2eeManager`)
- [x] Room connection accepts `e2ee` options in the connect dictionary (`livekit_room.cpp`, line 162)
- [x] E2EE manager auto-initializes after room connect (`livekit_room.cpp`, line 229)
- [x] E2EE signals wired from C++ delegate to Godot signal surface (`e2ee_state_changed`, `participant_encryption_status_changed`)
- [x] Key provider supports shared keys and per-participant keys with ratcheting
- [x] Frame cryptor supports per-participant enable/disable and key index selection
- [x] Unit tests for all E2EE classes in godot-livekit (`test/unit/test_e2ee.gd`, 11 tests)
- [x] Platform detection test for E2EE availability (`test/unit/test_platform.gd`)
- [ ] Release binaries built with `e2ee=yes` flag
- [ ] `LiveKitAdapter.connect_to_room()` passes E2EE options
- [ ] `LiveKitAdapter` connects E2EE signals (`e2ee_state_changed`, `participant_encryption_status_changed`)
- [ ] Key exchange mechanism (server-side or client-side passphrase)
- [ ] `AccordVoiceServerUpdate` carries encryption key or key exchange payload
- [ ] `Config.voice` E2EE preference persistence
- [ ] `AppState` E2EE signals
- [ ] UI: lock icon on encrypted voice channels
- [ ] UI: per-participant encryption status indicator
- [ ] UI: E2EE toggle in voice/video settings
- [ ] UI: shared key / passphrase entry for channel creators
- [ ] Error handling for mixed encrypted/unencrypted participants
- [ ] Message-level E2EE (text messages over REST/gateway — not covered by LiveKit E2EE)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| Release binaries not built with E2EE | High | `SConstruct` line 121 requires `e2ee=yes` build arg. Current release binaries from `build.sh` do not pass this flag. The LiveKit C++ SDK build must also include E2EE symbols. |
| No key exchange protocol | High | The server (`AccordVoiceServerUpdate`) has no field for encryption keys. Without a key exchange mechanism, clients have no way to agree on a shared key. Options: (a) server distributes a per-channel ephemeral key in the join response, (b) channel creator sets a passphrase that others must enter, (c) SAS (Short Authentication String) verification between participants. |
| `LiveKitAdapter` does not pass E2EE options | High | `connect_to_room()` (`livekit_adapter.gd`, line 72) passes `{"auto_reconnect": false}` — no `"e2ee"` key. Needs to construct `LiveKitE2eeOptions`, set the shared key, and include it in the options dictionary. |
| `LiveKitAdapter` does not connect E2EE signals | High | The two E2EE signals (`e2ee_state_changed`, `participant_encryption_status_changed`) emitted by `LiveKitRoom` (lines 723-743 of `livekit_room.cpp`) are not connected in `connect_to_room()` (`livekit_adapter.gd`, lines 62-71). |
| No E2EE config persistence | Medium | `config_voice.gd` has no `get_e2ee_enabled()` / `set_e2ee_enabled()` methods. User preference for E2EE should be persisted per-profile. |
| No AppState E2EE signals | Medium | `app_state.gd` has no signals for E2EE status changes. UI components need `e2ee_status_changed(user_id, is_encrypted)` to render lock icons. |
| No UI for encryption status | Medium | No lock icon on voice channel items, no per-participant encryption badge, no E2EE toggle in voice settings. |
| HTTPS fallback weakens transport security | Low | `add_server_dialog.gd` (line 214) falls back from HTTPS to HTTP if TLS fails. This is a separate concern from E2EE but means transport encryption is not guaranteed for REST/gateway traffic. |
| No message-level E2EE | Low | LiveKit E2EE covers only voice/video media. Text messages sent via REST and gateway WebSocket are protected by TLS in transit but are readable by the server. Message-level E2EE would require a separate encryption layer (e.g., Signal Protocol / Double Ratchet). |
| `ClassDB.class_exists()` runtime guard needed | Medium | Since E2EE classes are conditionally compiled, daccord code must check `ClassDB.class_exists("LiveKitE2eeOptions")` at runtime before attempting to use them — same pattern as `test_e2ee.gd` line 7. Otherwise, the client crashes on non-E2EE builds. |
