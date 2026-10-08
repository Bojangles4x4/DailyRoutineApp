const CACHE_NAME = 'daily-routine-v1-32-0-build-34-protected-sync-recovery';
const ASSETS = ['./','./index.html','./styles.css','./sync-core.js','./sync-cloud.js','./data-health.js','./app.js?v=1.32.0-build34-protected-sync-recovery','./manifest.webmanifest','./icon-192.png','./icon-512.png','./privacy.html','./support.html','./legal.css'];

self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE_NAME).then(cache => cache.addAll(ASSETS)));
  self.skipWaiting();
});

self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key !== CACHE_NAME).map(key => caches.delete(key)))));
  self.clients.claim();
});

self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  event.respondWith(
    fetch(event.request)
      .then(response => {
        const copy = response.clone();
        caches.open(CACHE_NAME).then(cache => cache.put(event.request, copy));
        return response;
      })
      .catch(() => caches.match(event.request).then(cached => cached || caches.match('./index.html')))
  );
});
