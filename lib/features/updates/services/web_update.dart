/// Web service-worker update bridge. Detects when a newer build has been
/// deployed (a new `flutter_service_worker.js` installed in the background) and
/// applies it by skipping the waiting worker and reloading. Backed by the hooks
/// defined in `web/index.html`; a no-op on every non-web platform.
///
/// The platform split is via conditional import so the rest of the app can call
/// these unconditionally.
library;

import 'package:bonfire/features/updates/services/web_update_stub.dart'
    if (dart.library.js_interop) 'package:bonfire/features/updates/services/web_update_web.dart'
    as impl;

/// Whether a freshly-deployed build is waiting to be loaded (web only).
bool webUpdateAvailable() => impl.webUpdateAvailable();

/// Activates the waiting build and reloads the page (web only).
void applyWebUpdate() => impl.applyWebUpdate();
