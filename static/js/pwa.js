/* Strata PWA - service worker registration and install prompt */

/* Register service worker */
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/static/sw.js', { scope: '/' })
      .catch((err) => console.warn('[strata/sw] registration failed:', err));
  });
}

/* Install prompt ("Add to Home Screen") */
let _deferredInstallPrompt = null;

window.addEventListener('beforeinstallprompt', (e) => {
  e.preventDefault();
  _deferredInstallPrompt = e;
  const btn = document.getElementById('pwa-install-btn');
  if (btn) btn.hidden = false;
});

window.addEventListener('appinstalled', () => {
  _deferredInstallPrompt = null;
  const btn = document.getElementById('pwa-install-btn');
  if (btn) btn.hidden = true;
});

function strataInstallApp() {
  if (!_deferredInstallPrompt) return;
  _deferredInstallPrompt.prompt();
  _deferredInstallPrompt.userChoice.then(() => {
    _deferredInstallPrompt = null;
    const btn = document.getElementById('pwa-install-btn');
    if (btn) btn.hidden = true;
  });
}

/* Mobile sidebar toggle */
function strataMobileSidebarOpen() {
  const sb = document.querySelector('.channel-sidebar');
  const overlay = document.getElementById('mobile-overlay');
  if (sb) sb.classList.add('mobile-open');
  if (overlay) overlay.hidden = false;
}

function strataMobileSidebarClose() {
  const sb = document.querySelector('.channel-sidebar');
  const overlay = document.getElementById('mobile-overlay');
  if (sb) sb.classList.remove('mobile-open');
  if (overlay) overlay.hidden = true;
}
