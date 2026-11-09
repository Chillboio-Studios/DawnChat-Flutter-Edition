self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  if (typeof event.notification.data === 'string') {
    event.waitUntil(self.clients.openWindow(event.notification.data));
  }
});

self.addEventListener('push', (event) => {
  if (!event.data) return;
  const n = JSON.parse(event.data.text());

  if (!n.title) {
    if (n.channel) {
      n.title = n.channel.channel_type === 'DirectMessage'
        ? (n.author || 'DawnChat')
        : `${n.author} in ${n.channel.name}`;
    } else {
      n.title = 'DawnChat';
    }
  }
  n.url ||= self.registration.scope;

  event.waitUntil(
    self.registration.showNotification(n.title || 'DawnChat', {
      icon: n.icon,
      body: n.body,
      data: n.url,
    }),
  );
});
