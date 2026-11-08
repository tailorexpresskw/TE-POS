/* Browser capabilities stay here; Flutter screens use a platform bridge. */
(() => {
  let installPrompt;
  let openInbox = new URL(location.href).searchParams.get('notifications') === '1';
  const registration = window.isSecureContext && 'serviceWorker' in navigator
    ? navigator.serviceWorker.register(new URL('sw.js', document.baseURI), {scope: new URL('./', document.baseURI).pathname, updateViaCache: 'none'})
    : Promise.resolve(null);
  registration.catch(() => {});
  window.addEventListener('beforeinstallprompt', event => { event.preventDefault(); installPrompt = event; });
  navigator.serviceWorker?.addEventListener('message', event => {
    if (event.data?.type === 'open-notifications') openInbox = true;
  });
  const standalone = () => matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
  function supported() { return window.isSecureContext && 'Notification' in window && 'PushManager' in window && 'serviceWorker' in navigator; }
  window.tePos = {
    consumeOpen() { const value = openInbox; openInbox = false; return value; },
    async install() {
      if (standalone()) return 'The POS is already installed.';
      if (installPrompt) { const prompt = installPrompt; installPrompt = null; await prompt.prompt(); const result = await prompt.userChoice; return result.outcome === 'accepted' ? 'POS app installed.' : 'Installation cancelled.'; }
      return /iPad|iPhone|iPod/.test(navigator.userAgent)
        ? 'In Safari, tap Share, then Add to Home Screen.'
        : 'Use your browser menu and choose Install app or Add to Home Screen.';
    },
    async state() {
      const reg = await registration.catch(() => null);
      const sub = reg ? await reg.pushManager?.getSubscription() : null;
      return JSON.stringify({supported: supported(), permission: 'Notification' in window ? Notification.permission : 'unsupported', subscribed: Boolean(sub)});
    },
    async subscribe(publicKey) {
      if (!supported()) throw new Error('Use HTTPS and a browser that supports notifications. On iPhone or iPad, add the POS to your Home Screen first.');
      // Ask immediately, while the Enable button still has user activation.
      const permission = await Notification.requestPermission();
      if (permission !== 'granted') throw new Error('Notifications are not allowed. You can change this in your browser settings.');
      const reg = await registration;
      if (!reg) throw new Error('The app service worker is unavailable. Reload and try again.');
      await navigator.serviceWorker.ready;
      const encoded = publicKey.replace(/-/g, '+').replace(/_/g, '/');
      const key = Uint8Array.from(atob(encoded + '='.repeat((4 - encoded.length % 4) % 4)), c => c.charCodeAt(0));
      let sub = await reg.pushManager.getSubscription();
      if (sub) {
        const existing = sub.options.applicationServerKey;
        if (existing && btoa(String.fromCharCode(...new Uint8Array(existing))).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_') !== publicKey) { await sub.unsubscribe(); sub = null; }
      }
      sub ??= await reg.pushManager.subscribe({userVisibleOnly: true, applicationServerKey: key});
      return JSON.stringify(sub.toJSON());
    },
    async unsubscribe() {
      const reg = await registration.catch(() => null);
      const sub = reg ? await reg.pushManager?.getSubscription() : null;
      const endpoint = sub?.endpoint || '';
      if (sub && !await sub.unsubscribe()) throw new Error('Could not disable device notifications. Try again.');
      return endpoint;
    },
    async subscription() {
      const reg = await registration.catch(() => null);
      const sub = reg ? await reg.pushManager?.getSubscription() : null;
      return sub ? JSON.stringify(sub.toJSON()) : '';
    },
  };
})();
