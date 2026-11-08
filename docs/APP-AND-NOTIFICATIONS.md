# Installable POS and notifications

The POS is a Flutter web app with a web app manifest, install icons and a service worker. It can be added to a device's home screen or desktop and opens in its own app window. It continues to use the same server, accounts, branch permissions and database.

## Install and enable alerts

Host the Node server on your own HTTPS domain with persistent storage. GitHub stores the source; GitHub Pages alone cannot run the Node server or SQLite database. Localhost can be used for desktop development, but another device needs a reachable HTTPS address.

- **Desktop and Android:** open the POS in a supported browser, then use **Account → Install POS app**, or the browser's install option.
- **iPhone and iPad:** open the HTTPS site in Safari, choose **Share → Add to Home Screen**, and open that installed icon. Web Push is supported for Home Screen web apps on iOS/iPadOS 16.4 and newer.
- Sign in, tap the bell, and choose **Enable device alerts**. Permission is requested only after that button is tapped. Each device needs its own permission.
- The bell inbox works even if device alerts are declined or unsupported. It refreshes while the app is open, and unread state is retained on the server.

The first alerts are:

- A new invoice assignment for its assigned tailor.
- Completed jobs and jobs put on hold for Reception, Managers and Admin within their permitted branches.

Notifications never give a tailor access to another tailor's jobs or a branch access to another branch's invoices. Reassigned, voided and refunded jobs are filtered out where appropriate. The lock-screen message is generic; customers, garment notes, invoice amounts and phone numbers are not included. Opening an alert focuses the existing POS window without reloading an unsaved cart.

## Server setup and delivery

A source checkout needs `npm ci --omit=dev` before starting. Use `npm ci` when you also need schema and type-checking tools. The standalone ZIP already includes the small runtime dependency set.

The server creates a stable VAPID key pair at `data/web-push.json` automatically. Keep and back up this private file with the database. It is ignored by Git and excluded from release packages. Optional host secrets are `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY` and `VAPID_SUBJECT` (a contact HTTPS URL or `mailto:` address). Both key variables must be supplied together. After deliberately rotating keys, disable and enable device alerts again on each device.

The server must stay running and reach browser push services over HTTPS. A background worker checks queued unread notifications about every 15 seconds. Successful deliveries are recorded per device; transient errors retry up to five times, and expired subscriptions are removed. Delivery is subject to browser permission, connectivity, device settings and Focus/Do Not Disturb. The inbox remains the durable record.

Signing out through the POS removes that browser's server subscription and disables its device subscription. Signing in as another account binds an existing subscription to that account. Use `DISABLE_WEB_PUSH=1` to disable background delivery while keeping the inbox.

The service worker caches only the offline connection screen and a public icon. It does not cache API responses, invoices, customer data or documents. Offline invoice entry and payment synchronization have not been implemented.

## Adding features and later native apps

Keep new business rules and notification types in `lib/`, new Flutter screens in `frontend/lib/`, and persistent changes in `db/schema.ts` plus an additive Drizzle migration. Keep API permissions and tests with each feature. New staff roles, reports, integrations and workflows can be added without replacing the web app.

The same Flutter screens and JSON APIs form the base for future Android and iOS apps. Native store builds are a later implementation stage, including:

1. Generate Android/iOS platform projects with stable application identifiers and configure signing. iOS release builds need macOS/Xcode and the appropriate Apple developer setup.
2. Implement a native HTTP session client with secure cookie or token persistence. The current web client relies on browser-managed same-origin session cookies.
3. Implement the platform bridge for native file picking, invoice PDF printing/sharing and external links; the existing browser adapter is isolated in `browser_web.dart`.
4. Add APNs/FCM device registration and delivery behind the notification service. The current sender implements standards-based Web Push, not native app push.
5. Test phone layouts, printers, permissions, background behavior and App Store/Google Play release requirements before distributing native builds.

Native binaries are not included in this version. Web installability does not require publishing to an app store.

References: [MDN installable PWAs](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Making_PWAs_installable), [Apple Web Push for Home Screen apps](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/), [Flutter platform guidance](https://docs.flutter.dev/platform-integration/web/faq).
