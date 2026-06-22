/* Strata service worker - handles Web Push notifications */

const CACHE_NAME = 'strata-v1';
const SHELL_ASSETS = [
  '/',
  '/static/css/strata.css',
  '/static/js/theme.js'
];

/* Install: cache the app shell */
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(SHELL_ASSETS))
  );
  self.skipWaiting();
});

/* Activate: claim clients immediately */
self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

/* Fetch: network-first for API calls, cache-first for static assets */
self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  if (url.pathname.startsWith('/static/')) {
    event.respondWith(
      caches.match(event.request).then((cached) =>
        cached || fetch(event.request)
      )
    );
  }
});

/* Push: display the notification */
self.addEventListener('push', (event) => {
  let data = { title: 'Strata', body: 'You have a new notification.' };
  if (event.data) {
    try {
      data = event.data.json();
    } catch (e) {
      data.body = event.data.text();
    }
  }
  const options = {
    body:    data.body  || '',
    icon:    data.icon  || '/static/icons/icon-192.png',
    badge:   '/static/icons/badge-72.png',
    tag:     data.tag   || 'strata-notification',
    renotify: true,
    data:    { url: data.url || '/' }
  };
  event.waitUntil(
    self.registration.showNotification(data.title, options)
  );
});

/* Notification click: focus or open the app */
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = event.notification.data.url || '/';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const client of list) {
        if (client.url === target && 'focus' in client) {
          return client.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow(target);
      }
    })
  );
});
