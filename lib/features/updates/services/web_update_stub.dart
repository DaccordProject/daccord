/// Non-web implementation of the web service-worker update bridge: there is no
/// service worker off the web, so nothing is ever available and apply is a no-op.
library;

bool webUpdateAvailable() => false;

void applyWebUpdate() {}
