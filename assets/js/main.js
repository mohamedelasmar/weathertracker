// Service Worker for Weather Tracker
// Provides offline functionality and caching

const CACHE_NAME = 'weather-tracker-v1';
const urlsToCache = [
  '/',
  '/index.html',
  '/css/main.css',
  '/js/main.js',
  '/images/sunny.svg',
  '/images/cloudy.svg',
  '/images/rainy.svg',
  '/images/snowy.svg',
  '/images/thunderstorm.svg',
  '/images/windy.svg'
];

// Install event - cache resources
self.addEventListener('install', event => {
  console.log('Service Worker: Installing...');
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => {
        console.log('Service Worker: Caching files');
        return cache.addAll(urlsToCache);
      })
      .then(() => {
        console.log('Service Worker: Installation complete');
        return self.skipWaiting();
      })
      .catch(error => {
        console.error('Service Worker: Installation failed', error);
      })
  );
});

// Activate event - clean up old caches
self.addEventListener('activate', event => {
  console.log('Service Worker: Activating...');
  event.waitUntil(
    caches.keys().then(cacheNames => {
      return Promise.all(
        cacheNames.map(cacheName => {
          if (cacheName !== CACHE_NAME) {
            console.log('Service Worker: Deleting old cache', cacheName);
            return caches.delete(cacheName);
          }
        })
      );
    }).then(() => {
      console.log('Service Worker: Activation complete');
      return self.clients.claim();
    })
  );
});

// Fetch event - serve cached content when offline
self.addEventListener('fetch', event => {
  event.respondWith(
    caches.match(event.request)
      .then(response => {
        // Return cached version or fetch from network
        if (response) {
          console.log('Service Worker: Serving from cache', event.request.url);
          return response;
        }

        console.log('Service Worker: Fetching from network', event.request.url);
        return fetch(event.request).then(response => {
          // Don't cache non-successful responses
          if (!response || response.status !== 200 || response.type !== 'basic') {
            return response;
          }

          // Clone response as it can only be consumed once
          const responseToCache = response.clone();

          caches.open(CACHE_NAME)
            .then(cache => {
              cache.put(event.request, responseToCache);
            });

          return response;
        }).catch(() => {
          // If both cache and network fail, show offline page
          if (event.request.destination === 'document') {
            return caches.match('/index.html');
          }
        });
      })
  );
});

// Background sync for weather data updates
self.addEventListener('sync', event => {
  if (event.tag === 'weather-data-sync') {
    event.waitUntil(syncWeatherData());
  }
});

async function syncWeatherData() {
  console.log('Service Worker: Syncing weather data...');
  try {
    // This would typically sync with your OCI backend
    const response = await fetch('/api/weather/sync', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      }
    });
    
    if (response.ok) {
      console.log('Service Worker: Weather data synced successfully');
      
      // Notify the main app
      self.clients.matchAll().then(clients => {
        clients.forEach(client => {
          client.postMessage({
            type: 'WEATHER_DATA_SYNCED',
            timestamp: Date.now()
          });
        });
      });
    }
  } catch (error) {
    console.error('Service Worker: Weather data sync failed', error);
  }
}

// Push notifications for weather alerts
self.addEventListener('push', event => {
  console.log('Service Worker: Push notification received');
  
  let notificationData = {};
  
  if (event.data) {
    try {
      notificationData = event.data.json();
    } catch (e) {
      notificationData = {
        title: 'Weather Alert',
        body: event.data.text() || 'Weather conditions have changed',
        icon: '/images/cloudy.svg',
        badge: '/images/weather-badge.png'
      };
    }
  }

  const notificationOptions = {
    body: notificationData.body || 'Weather conditions have changed',
    icon: notificationData.icon || '/images/cloudy.svg',
    badge: notificationData.badge || '/images/weather-badge.png',
    vibrate: [200, 100, 200],
    tag: 'weather-alert',
    requireInteraction: true,
    actions: [
      {
        action: 'view',
        title: 'View Details',
        icon: '/images/view-icon.png'
      },
      {
        action: 'close',
        title: 'Dismiss',
        icon: '/images/close-icon.png'
      }
    ],
    data: {
      url: notificationData.url || '/',
      alertId: notificationData.alertId
    }
  };

  event.waitUntil(
    self.registration.showNotification(
      notificationData.title || 'Weather Alert',
      notificationOptions
    )
  );
});

// Handle notification clicks
self.addEventListener('notificationclick', event => {
  console.log('Service Worker: Notification clicked', event);
  
  event.notification.close();
  
  if (event.action === 'view') {
    // Open the app
    event.waitUntil(
      clients.openWindow(event.notification.data.url || '/')
    );
  } else if (event.action === 'close') {
    // Just close the notification
    return;
  } else {
    // Default action - open the app
    event.waitUntil(
      clients.matchAll({ type: 'window' }).then(clientList => {
        for (let i = 0; i < clientList.length; i++) {
          const client = clientList[i];
          if (client.url === '/' && 'focus' in client) {
            return client.focus();
          }
        }
        if (clients.openWindow) {
          return clients.openWindow('/');
        }
      })
    );
  }
});

// Handle messages from the main app
self.addEventListener('message', event => {
  console.log('Service Worker: Message received', event.data);
  
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
  
  if (event.data && event.data.type === 'REQUEST_SYNC') {
    // Register background sync
    self.registration.sync.register('weather-data-sync');
  }
});

// Periodic background sync (if supported)
self.addEventListener('periodicsync', event => {
  if (event.tag === 'weather-update') {
    event.waitUntil(syncWeatherData());
  }
});

// Handle online/offline status
self.addEventListener('online', event => {
  console.log('Service Worker: Online');
  syncWeatherData();
});

self.addEventListener('offline', event => {
  console.log('Service Worker: Offline');
});