/* MAKE IT app shell registration. Network data stays live and is never cached here. */
self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));
