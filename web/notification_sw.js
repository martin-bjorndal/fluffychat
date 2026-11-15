// SPDX-FileCopyrightText: 2026 Martin Bjørndal
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Hanne Chat: shows the web app's notifications. Safari on an iPhone has no
// `new Notification()`; a web app on the home screen can only show them
// through a service worker (lib/gruppechat/web_notifications_browser.dart).
// Registered under the scope notification_sw/, so it controls no page and
// handles no requests.
'use strict';

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  let data = {};
  try {
    data = JSON.parse(event.notification.data || '{}') || {};
  } catch (e) {}
  // The app's base: the scope's parent
  const base = new URL('..', self.registration.scope).href;
  event.waitUntil(
    (async () => {
      const windows = await self.clients.matchAll({
        type: 'window',
        includeUncontrolled: true,
      });
      const app = windows.find((w) => w.url.startsWith(base));
      if (app) {
        try {
          await app.focus();
        } catch (e) {}
        if (data.payload) {
          app.postMessage(JSON.stringify({ type: 'open', payload: data.payload }));
        }
        return;
      }
      await self.clients.openWindow(new URL(data.link || '', base).href);
    })()
  );
});
