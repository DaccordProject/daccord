/// Web implementation of the service-worker update bridge. Reads the flags set
/// by `web/index.html`: `daccordUpdateAvailable` flips to true once a new
/// service worker has installed in the background, and `daccordApplyUpdate()`
/// activates it and reloads.
library;

import 'dart:js_interop';

@JS('daccordUpdateAvailable')
external JSBoolean? get _available;

@JS('daccordApplyUpdate')
external JSFunction? get _apply;

bool webUpdateAvailable() => _available?.toDart ?? false;

void applyWebUpdate() => _apply?.callAsFunction();
