## Web Audio API bridge for mic test level meter and monitor playback.
##
## On web, AudioStreamMicrophone cannot be sampled by Godot's audio engine.
## This helper uses getUserMedia + AnalyserNode to compute RMS for the level
## meter, and a GainNode for monitor (loopback) playback.

var _monitor_active: bool = false


func start_analyser() -> void:
	if OS.get_name() != "Web":
		return
	JavaScriptBridge.eval("""
	(function() {
		if (window._daccordMicAnalyser) return;
		var ctx = new (window.AudioContext || window.webkitAudioContext)();
		navigator.mediaDevices.getUserMedia({ audio: true }).then(function(stream) {
			var src = ctx.createMediaStreamSource(stream);
			var analyser = ctx.createAnalyser();
			analyser.fftSize = 2048;
			src.connect(analyser);
			window._daccordMicAnalyser = {
				ctx: ctx, stream: stream, src: src, analyser: analyser,
				buf: new Float32Array(analyser.fftSize)
			};
		});
	})();
	""", true)


func stop_analyser() -> void:
	if OS.get_name() != "Web":
		return
	JavaScriptBridge.eval("""
	(function() {
		var a = window._daccordMicAnalyser;
		if (!a) return;
		a.src.disconnect();
		a.stream.getTracks().forEach(function(t) { t.stop(); });
		if (a.ctx.state !== 'closed') a.ctx.close();
		window._daccordMicAnalyser = null;
	})();
	""", true)


func get_rms() -> float:
	if OS.get_name() != "Web":
		return 0.0
	var val: float = JavaScriptBridge.eval("""
	(function() {
		var a = window._daccordMicAnalyser;
		if (!a) return 0.0;
		a.analyser.getFloatTimeDomainData(a.buf);
		var sum = 0.0;
		for (var i = 0; i < a.buf.length; i++) sum += a.buf[i] * a.buf[i];
		return Math.sqrt(sum / a.buf.length);
	})();
	""", true)
	return val


func start_monitor() -> void:
	if OS.get_name() != "Web" or _monitor_active:
		return
	_monitor_active = true
	JavaScriptBridge.eval("""
	(function() {
		if (window._daccordMicMonitor) return;
		var a = window._daccordMicAnalyser;
		if (!a) return;
		var gain = a.ctx.createGain();
		gain.gain.value = 1.0;
		a.src.connect(gain);
		gain.connect(a.ctx.destination);
		window._daccordMicMonitor = { gain: gain };
	})();
	""", true)


func stop_monitor() -> void:
	if OS.get_name() != "Web" or not _monitor_active:
		return
	_monitor_active = false
	JavaScriptBridge.eval("""
	(function() {
		var m = window._daccordMicMonitor;
		if (!m) return;
		m.gain.disconnect();
		window._daccordMicMonitor = null;
	})();
	""", true)


func set_monitor_gate(open: bool) -> void:
	if OS.get_name() != "Web" or not _monitor_active:
		return
	var val: float = 1.0 if open else 0.0
	JavaScriptBridge.eval(
		"if(window._daccordMicMonitor) window._daccordMicMonitor.gain.gain.value=%f;" % val,
		true
	)
