# Tailor Express POS

The employee app is Flutter Web. It uses the supplied desktop screenshots for its navigation, green/white/purple theme, category list, service grid, cart, keypad and dialogs. At smaller widths, Items and Cart become separate tabs. Phones, tablets and desktop computers use the same browser app and server database. Native Windows, macOS, Android and iOS packages are not included in this delivery.

## Implemented

- Ten branches from the location screenshot, with server-enforced branch permissions.
- The 446 item codes, categories and prices from the supplied Excel workbook. The workbook takes precedence where screenshot prices differ. Original labels and zero-priced services are retained; zero prices prompt staff for a service price. Arabic service descriptions are generated from a small translation map, not imported translations.
- Customers, quotations, held orders, quantities, service prices, coupons, notes, collection date, assigned employee and partner name.
- Unpaid, partial and split payments, a payment ledger, balance collection, payment-method corrections and full refunds. Cash, K-NET, card and bank-transfer methods record payments received externally. No terminal or payment gateway is connected.
- Sales list, delivery statuses, clone bill, receipt/reprint, branch reports, CSV export, petty expenses and administrator branch summaries.
- PDF/image document attachments in R2, limited to 5 MB per file and 10 per order.
- Staff access by email, roles, branch assignments, catalogue price overrides and audit history. Manager permissions cover custom fixed prices, manual discounts, extra charges, refunds, voids and payment-method corrections. Cashiers can set prices only on services whose catalogue price is zero.

## Access and first use

The initial publication is private to its owner. The first authenticated owner initializes the administrator record automatically. This bootstrap assumes the Site remains owner-private until initialized. Do not open visitor access before initializing it.

1. Sign in, select a branch, and review the catalogue against the workbook.
2. Use Administration to assign staff emails, roles and branches. Each staff member uses their own ChatGPT account with that email. Staff permissions do not themselves change the hosting platform's visitor policy. Configure approved visitor access separately before rollout.
3. Test real printer paper size and the business's receipt details. Print opens the browser's printable receipt in a new tab. Automatic silent printer operation is not configured.
4. Train employees to use Hold before leaving a till. Unsaved carts exist only in the current app session. The app requires an internet connection to save orders and payments; it does not provide offline transaction synchronization.
5. Review discounts, refund authority and accounting treatment before using the new ledger for live operations.

Production starts empty. Screenshot customer data and local test transactions are not imported. The two initial coupons, Dar Usha (15%) and Family and Friends (20%), follow the provided reference screen. Voucher balances, packages, stock management, cash-drawer/shift reconciliation and automated accounting are not implemented.

## Local development

Prerequisites: Flutter 3.35.6 or compatible, Node >=22.13, npm, Git. The Flutter frontend is in `frontend/`; the TypeScript API is in `lib/service.ts` with routes under `app/api/`. The framework shell at `/` redirects to Flutter at `/pos/`; no React employee screens are used.

```powershell
npm run install:ci
cd frontend
flutter pub get
flutter test --dart-define=API_URL=http://localhost
cd ..
$env:FLUTTER_BIN = 'C:/path/to/flutter/bin/flutter.bat'
node scripts/build-flutter.mjs
node path/to/sites/scripts/build-site.mjs
```

Generate future schema migrations with `npm run db:generate`. Apply pending migrations to the local D1 database using the starter's documented Wrangler commands and `.wrangler/state`. Never replay applied migrations. Build output includes all Flutter rendering resources; it does not rely on the Flutter rendering CDN.

For a built local preview, use `npm start -- --port 8787`. Local built-preview API tests can provide identity headers; public deployment identity is supplied by the hosting platform. Do not expose the local preview to the network or accept client-supplied identity headers on a different host without a trusted authentication layer. `scripts/api-smoke.mjs` refuses non-loopback URLs and writes test records only into the local database.

```powershell
node --experimental-strip-types --test lib/domain.test.mjs
node scripts/api-smoke.mjs http://127.0.0.1:8787
```

Use the Vinext development preview when simulating Sign in with ChatGPT locally, as described in the starter documentation. `API_URL` can point the Flutter app at a local API during development. Production uses same-origin `/api/` requests; do not enable broad CORS or expose private keys in Flutter code.

## Data and recovery

Money is stored as integer fils (1 KWD = 1,000 fils). Receipts retain the original line prices and customer snapshot. Business-day filters use Asia/Kuwait. Amount Received uses payment dates; sales totals use original sale dates. Category reports show gross line amounts before order discounts and extra charges. Lists are bounded to 1,000 orders and expenses and 5,000 payments per date range; use shorter ranges for busy branches.

Order creation and expense recording have client-generated idempotency keys. Payments use idempotency keys, order versions and conditional database transactions to reject conflicting collections. Held-order conversion uses a unique source marker so two devices cannot convert the same held order twice. Refunds retain the sale and add a negative payment entry. Delete Sale marks an unpaid sale void; records are retained.

Never commit `.env` files, credentials, `.wrangler/`, `.sites-runtime/`, runtime databases or uploaded customer files. Configure hosting secrets through the hosting platform. Keep private source repositories and limit collaborator permissions. Establish database and document backups, retention rules and a tested restore procedure with the chosen hosting provider before live branch rollout; CSV exports are reports, not complete backups.

## Booking and inventory later

Branch IDs and item codes are stable. Orders reserve `booking_id` for future integration and `external_id` for unique import/conversion references. Booking and inventory are currently separate and unchanged. Before connecting them, map their branch IDs, define which application owns each record, add authenticated integration endpoints, and implement an outbox/consumer with unique event IDs so retries cannot duplicate orders or inventory movements. Do not decrement stock for alteration services as though they were physical items. Inventory effects of returns and cancellations must be defined when stock integration is added.
