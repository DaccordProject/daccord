// Sentry integration for Daccord web builds.
// Lazy-loads the Sentry JS SDK from CDN when init() is called, so no
// network requests happen until the user opts in to crash reporting.
(function () {
  "use strict";

  var SDK_URL =
    "https://browser.sentry-cdn.com/9.5.0/bundle.tracing.min.js";
  var _ready = false;
  var _queue = [];

  function _loadScript(url, cb) {
    var s = document.createElement("script");
    s.src = url;
    s.crossOrigin = "anonymous";
    s.onload = function () { cb(null); };
    s.onerror = function () { cb(new Error("Failed to load Sentry SDK")); };
    document.head.appendChild(s);
  }

  function _flush() {
    for (var i = 0; i < _queue.length; i++) {
      _queue[i]();
    }
    _queue = [];
  }

  function _enqueue(fn) {
    if (_ready) { fn(); } else { _queue.push(fn); }
  }

  window.daccordSentry = {
    init: function (dsn, environment, release) {
      if (_ready) return;
      _loadScript(SDK_URL, function (err) {
        if (err || typeof Sentry === "undefined") {
          console.warn("[daccord-sentry] Could not load Sentry SDK");
          return;
        }
        Sentry.init({
          dsn: dsn,
          environment: environment || "web",
          release: release || undefined,
          sampleRate: 1.0,
          beforeSend: function (event) {
            // Strip potential PII from messages
            if (event.message) {
              event.message = event.message
                .replace(/Bearer\s+[A-Za-z0-9._\-]+/g, "Bearer [REDACTED]")
                .replace(/token=[^&\s"']+/g, "token=[REDACTED]")
                .replace(/dk_[0-9a-fA-F]{8,}/g, "[TOKEN REDACTED]")
                .replace(/\b[0-9a-fA-F]{64}\b/g, "[TOKEN REDACTED]")
                .replace(
                  /https?:\/\/[^\s"']+:\d{2,5}[^\s"']*/g,
                  "[URL REDACTED]"
                );
            }
            return event;
          },
        });
        _ready = true;
        _flush();
      });
    },

    captureMessage: function (msg, level) {
      _enqueue(function () {
        Sentry.captureMessage(msg, level || "info");
      });
    },

    addBreadcrumb: function (message, category, type) {
      _enqueue(function () {
        Sentry.addBreadcrumb({
          message: message,
          category: category || "default",
          type: type || "default",
        });
      });
    },

    setTag: function (key, value) {
      _enqueue(function () {
        Sentry.setTag(key, value);
      });
    },

    isReady: function () {
      return _ready;
    },
  };
})();
