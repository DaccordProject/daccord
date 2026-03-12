/**
 * godot-livekit-web.js
 *
 * JavaScript wrapper around livekit-client.js that mirrors the godot-livekit
 * GDExtension API surface.  Godot web exports use JavaScriptBridge to call
 * into this wrapper, giving GDScript the same method names and event semantics
 * as the native C++ GDExtension.
 *
 * Prerequisites: livekit-client UMD bundle must be loaded first so that
 * `window.LivekitClient` is available.
 *
 * IMPORTANT: Godot's JavaScriptBridge cannot call methods on wrapped JS
 * objects (obj[method] lookup fails at the WASM/JS boundary).  Therefore:
 *   - The room object uses plain own-property functions (no prototypes).
 *   - Event callback data uses plain data properties (not getter methods)
 *     so GDScript can read them via obj["property"].
 *   - All GDScript interaction goes through JavaScriptBridge.eval().
 *
 * Usage from GDScript (via JavaScriptBridge):
 *   JavaScriptBridge.eval("window._godotLkRoom = GodotLiveKit.createRoom()", true)
 *   JavaScriptBridge.eval("window._godotLkRoom.connectToRoom(url, token)", true)
 */
(function (global) {
  "use strict";

  var LK = global.LivekitClient;
  if (!LK) {
    console.error(
      "[godot-livekit-web] LivekitClient not found. " +
        "Load livekit-client.umd.min.js before this script."
    );
    return;
  }

  // Enable verbose LiveKit logging for debugging WebRTC issues.
  if (LK.setLogLevel) {
    LK.setLogLevel("debug");
  }

  // --- Constants matching GDExtension enums ---

  var ConnectionState = {
    DISCONNECTED: 0,
    CONNECTING: 1,
    CONNECTED: 2,
    RECONNECTING: 3,
    FAILED: 4,
  };

  var TrackKind = {
    AUDIO: 0,
    VIDEO: 1,
  };

  var TrackSource = {
    UNKNOWN: 0,
    CAMERA: 1,
    MICROPHONE: 2,
    SCREENSHARE: 3,
    SCREENSHARE_AUDIO: 4,
  };

  function mapConnectionState(state) {
    switch (state) {
      case LK.ConnectionState.Connecting:
        return ConnectionState.CONNECTING;
      case LK.ConnectionState.Connected:
        return ConnectionState.CONNECTED;
      case LK.ConnectionState.Reconnecting:
        return ConnectionState.RECONNECTING;
      default:
        return ConnectionState.DISCONNECTED;
    }
  }

  function mapTrackKind(kind) {
    switch (kind) {
      case LK.Track.Kind.Audio:
        return TrackKind.AUDIO;
      case LK.Track.Kind.Video:
        return TrackKind.VIDEO;
      default:
        return TrackKind.AUDIO;
    }
  }

  function mapTrackSource(source) {
    switch (source) {
      case LK.Track.Source.Camera:
        return TrackSource.CAMERA;
      case LK.Track.Source.Microphone:
        return TrackSource.MICROPHONE;
      case LK.Track.Source.ScreenShare:
        return TrackSource.SCREENSHARE;
      case LK.Track.Source.ScreenShareAudio:
        return TrackSource.SCREENSHARE_AUDIO;
      default:
        return TrackSource.UNKNOWN;
    }
  }

  // --- Data wrappers (plain data properties, no methods) ---
  // Godot can read these via obj["property"] but cannot call obj.method().

  function dataTrack(track) {
    if (!track) return null;
    return {
      kind: mapTrackKind(track.kind),
      source: mapTrackSource(track.source),
      sid: track.sid || "",
      isMuted: !!track.isMuted,
    };
  }

  function dataParticipant(participant) {
    if (!participant) return null;
    return {
      identity: participant.identity || "",
      sid: participant.sid || "",
      name: participant.name || "",
      metadata: participant.metadata || "",
    };
  }

  // --- Room factory (returns a plain object, no prototype) ---

  function createRoom() {
    var room = new LK.Room();
    var listeners = {};
    // participant SID -> HTMLAudioElement for remote audio tracks
    var audioElements = {};
    var isDeafened = false;

    function emit(event) {
      var cbs = listeners[event];
      if (!cbs) return;
      var args = Array.prototype.slice.call(arguments, 1);
      for (var i = 0; i < cbs.length; i++) {
        try {
          cbs[i].apply(null, args);
        } catch (e) {
          console.error("[godot-livekit-web] Error in", event, "handler:", e);
        }
      }
    }

    // --- Bind livekit-client room events ---

    room.on(LK.RoomEvent.Connected, function () {
      emit("connected");
    });

    room.on(LK.RoomEvent.Disconnected, function (reason) {
      emit("disconnected", reason || "");
    });

    room.on(LK.RoomEvent.Reconnecting, function () {
      emit("reconnecting");
    });

    room.on(LK.RoomEvent.Reconnected, function () {
      emit("reconnected");
    });

    room.on(LK.RoomEvent.ParticipantConnected, function (participant) {
      emit("participantConnected", dataParticipant(participant));
    });

    room.on(LK.RoomEvent.ParticipantDisconnected, function (participant) {
      emit("participantDisconnected", dataParticipant(participant));
    });

    room.on(
      LK.RoomEvent.TrackSubscribed,
      function (track, publication, participant) {
        // Attach remote audio tracks to the DOM for playback
        if (track.kind === LK.Track.Kind.Audio) {
          var el = document.createElement("audio");
          el.id = "lk-audio-" + participant.sid;
          el.autoplay = true;
          el.muted = isDeafened;
          track.attach(el);
          document.body.appendChild(el);
          audioElements[participant.sid] = el;
          console.log(
            "[godot-livekit-web] Attached audio element for",
            participant.identity,
            "srcObject:", !!el.srcObject
          );
        }
        emit(
          "trackSubscribed",
          dataTrack(track),
          null,
          dataParticipant(participant)
        );
      }
    );

    room.on(
      LK.RoomEvent.TrackUnsubscribed,
      function (track, publication, participant) {
        // Detach and remove audio elements
        if (track.kind === LK.Track.Kind.Audio) {
          var el = audioElements[participant.sid];
          if (el) {
            track.detach(el);
            el.remove();
            delete audioElements[participant.sid];
            console.log(
              "[godot-livekit-web] Detached audio element for",
              participant.identity
            );
          }
        }
        emit(
          "trackUnsubscribed",
          dataTrack(track),
          null,
          dataParticipant(participant)
        );
      }
    );

    room.on(LK.RoomEvent.TrackMuted, function (publication, participant) {
      emit("trackMuted", dataParticipant(participant), null);
    });

    room.on(LK.RoomEvent.TrackUnmuted, function (publication, participant) {
      emit("trackUnmuted", dataParticipant(participant), null);
    });

    room.on(LK.RoomEvent.ActiveSpeakersChanged, function (speakers) {
      var wrapped = [];
      for (var i = 0; i < speakers.length; i++) {
        var p = speakers[i];
        wrapped.push({
          identity: p.identity || "",
          audioLevel: p.audioLevel || 0,
        });
      }
      emit("activeSpeakersChanged", wrapped);
    });

    room.on(
      LK.RoomEvent.ConnectionQualityChanged,
      function (quality, participant) {
        emit(
          "connectionQualityChanged",
          dataParticipant(participant),
          quality
        );
      }
    );

    // --- Return plain object with all methods as own properties ---

    return {
      on: function (event, callback) {
        if (!listeners[event]) {
          listeners[event] = [];
        }
        listeners[event].push(callback);
      },

      off: function (event, callback) {
        var cbs = listeners[event];
        if (!cbs) return;
        var idx = cbs.indexOf(callback);
        if (idx !== -1) cbs.splice(idx, 1);
      },

      connectToRoom: function (url, token) {
        return room.connect(url, token).catch(function (err) {
          console.error("[godot-livekit-web] connectToRoom failed:", err);
          emit("disconnected", String(err));
        });
      },

      disconnectFromRoom: function () {
        return room.disconnect();
      },

      getConnectionState: function () {
        return mapConnectionState(room.state);
      },

      getLocalParticipant: function () {
        // Returns an object with callable methods for use from JS eval
        var lp = room.localParticipant;
        if (!lp) return null;
        return {
          identity: lp.identity || "",
          setMicrophoneEnabled: function (enabled) {
            return lp.setMicrophoneEnabled(enabled);
          },
          setCameraEnabled: function (enabled) {
            return lp.setCameraEnabled(enabled);
          },
          setScreenShareEnabled: function (enabled) {
            return lp.setScreenShareEnabled(enabled);
          },
        };
      },

      getSid: function () {
        return room.sid || "";
      },

      getName: function () {
        return room.name || "";
      },

      getMetadata: function () {
        return room.metadata || "";
      },

      setDeafened: function (deafened) {
        isDeafened = !!deafened;
        for (var sid in audioElements) {
          audioElements[sid].muted = isDeafened;
        }
      },

      cleanupAudio: function () {
        for (var sid in audioElements) {
          var el = audioElements[sid];
          el.srcObject = null;
          el.remove();
        }
        audioElements = {};
      },
    };
  }

  // --- Public API ---

  global.GodotLiveKit = {
    ConnectionState: ConnectionState,
    TrackKind: TrackKind,
    TrackSource: TrackSource,
    createRoom: createRoom,
  };
})(typeof globalThis !== "undefined" ? globalThis : this);
