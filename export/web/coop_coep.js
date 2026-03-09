/**
 * Service worker that injects Cross-Origin-Opener-Policy and
 * Cross-Origin-Embedder-Policy headers on every response.
 *
 * Godot 4 WASM needs SharedArrayBuffer for threading, which Chrome only
 * permits in "cross-origin isolated" contexts. A production server should
 * send these headers directly; this service worker provides the same
 * isolation for self-hosted / static-file deployments.
 *
 * Registration and the forced reload on first activation are handled in
 * index.html.
 */

"use strict";

self.addEventListener("install", () => {
  // Activate immediately — no need to wait for existing pages to close.
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  // Take control of all pages in the scope right away.
  event.waitUntil(self.clients.claim());
});

self.addEventListener("fetch", (event) => {
  // Only intercept same-origin requests; pass cross-origin requests
  // (CDN assets, livekit-client.js) through unmodified to avoid CORS issues.
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) {
    return;
  }

  event.respondWith(
    fetch(event.request).then((response) => {
      // Clone the response and add isolation headers.
      const headers = new Headers(response.headers);
      headers.set("Cross-Origin-Opener-Policy", "same-origin");
      headers.set("Cross-Origin-Embedder-Policy", "credentialless");
      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers,
      });
    })
  );
});
