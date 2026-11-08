const OFFLINE_CACHE = 'te-pos-offline-v1';
self.addEventListener('install', event => {
  event.waitUntil(caches.open(OFFLINE_CACHE).then(cache => cache.addAll(['./offline.html', './icons/app-192.png'])).then(() => self.skipWaiting()));
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key.startsWith('te-pos-offline-') && key !== OFFLINE_CACHE).map(key => caches.delete(key)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  // Never cache invoices, API responses, documents or authenticated user data.
  if (event.request.mode === 'navigate' && url.origin === self.location.origin && url.pathname.startsWith('/pos/')) {
    event.respondWith(fetch(event.request).catch(() => caches.match('./offline.html')));
  }
});
self.addEventListener('push', event => {
  let data = {};
  try { data = event.data?.json() || {}; } catch {}
  event.waitUntil(self.registration.showNotification('Tailor Express', {
    body: 'You have a new work notification. Open the POS to view it.',
    icon: './icons/app-192.png',
    tag: data.notificationId || 'te-pos-update',
    data: {url: new URL('./?notifications=1', self.registration.scope).href},
  }));
});
self.addEventListener('notificationclick', event => {
  event.notification.close();
  event.waitUntil(self.clients.matchAll({type: 'window', includeUncontrolled: true}).then(async windows => {
    const existing = windows.find(client => new URL(client.url).origin === self.location.origin && new URL(client.url).pathname.startsWith('/pos/'));
    if (existing) { await existing.focus(); existing.postMessage({type: 'open-notifications'}); }
    else await self.clients.openWindow(new URL('./?notifications=1', self.registration.scope).href);
  }));
});
