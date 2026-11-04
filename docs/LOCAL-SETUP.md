# Tailor Express POS — standalone Flutter web app

This is a regular, self-hosted web app. Staff sign in using their Tailor Express username and password. It runs independently of ChatGPT, OpenAI, Cloudflare Workers and D1. Nothing is uploaded automatically.

## Check it locally

1. Install Node.js 22.13 or newer.
2. First time only: run `Setup-Admin.cmd` to provision the initial administrator. This local command asks for your name, username and a hidden password. It preserves an existing administrator.
3. Double-click `Start-POS.cmd`, or run `npm start` from the app folder.
4. Visit **http://localhost:3000** and sign in. There is no public registration or browser-based initial-account creation.
5. In **Administration**, the Admin creates Manager, Reception and Tailor accounts, sets their passwords, and assigns their allowed branches.

Only Admin can create or change staff accounts. The initial local setup command (or private administrator environment variables on the server) exists solely to provision the first Admin. There is no preset password.

### Role dashboards and branch access

- **Admin:** overview of all branches, financial totals, unassigned work, tailor tracking, catalogue management and user administration.
- **Branch Manager:** branch dashboard, invoices, payments, reports, tailor assignments and progress corrections for assigned branches. Managers can apply financial overrides; only Admin manages user accounts and catalogue prices.
- **Reception:** the familiar POS and branch dashboard, customer invoices, payments and receipts. Staff can view and assign invoices only within their assigned branch access.
- **Tailor:** their own workload dashboard and tracking page. They can read the garment instructions and authorized documents for their assigned jobs, add progress notes, and move work through Pending, In Progress, On Hold and Completed. They cannot view invoice prices, payments, other tailors' jobs, the POS, or user administration.

Existing Cashier accounts are treated as Reception without deleting or replacing the accounts. Existing Branch Manager accounts retain their branch and financial permissions. Existing email logins continue to work; Admin can add usernames to these accounts without replacing them. New accounts use usernames (3?50 letters, numbers, dots, hyphens or underscores) and passwords.

### Customers and service instructions

Click **Walk-in customer** in the POS to search by name or phone, open a saved profile, edit contact details, view the selected branch's invoice history, or add a customer. Click **Select customer** to attach the saved customer to the invoice. Updating a profile does not rewrite previously issued invoices.

Choosing a service adds it straight to the Item Name list. Click that added service in the cart to enter or edit its garment notes or measurements, quantity and permitted price. Selecting from the catalogue does not open the notes dialog. The same service with different notes stays on separate invoice lines, and those instructions are included in tailor tracking and the invoice PDFs.

### Printing, assignment and manual WhatsApp

Reception can select a branch tailor during payment, or choose Assign later. The invoice/receipt screen also offers Assign tailor before printing. Assignment and reassignment are available later from the branch dashboard, Sales List and Tracking page. Only active tailors who belong to that invoice's branch can be selected. Reassigning work that has already started requires a reason and keeps the work history.

**Print receipt / Save PDF** opens the narrow receipt layout: 80 mm paper with a 72 mm content area, following the supplied invoice reference. Print at 100% scale with browser headers and footers off. Paper height adapts to the invoice content; choose your printer's matching 80 mm roll setting.

**WhatsApp invoice** opens a message preview and the customer's phone number. **Save WhatsApp PDF** opens a separate 108 mm wide layout with larger text for viewing on phones. Choose **Save as PDF** in the browser, then use **Open WhatsApp** and attach the saved file manually. Review the message and press Send yourself. The receipt screen also has **WhatsApp PDF / mobile layout** for direct access. No messages are sent automatically. Eight-digit local phone numbers use Kuwait's 965 country code; international numbers include their country code.

Tailor progress is tracked separately from the existing invoice/delivery status. Reception continues to handle Prepared, Packed, Delivered and Closed in the usual sales workflow. Progress notes, assignment changes and work-status changes are retained in the job history and audit trail.

Keep the server terminal open while using the app. The compiled Flutter app is included under `public/pos`, so Flutter and npm dependency installation are not needed just to run this package.

## Your data

The SQLite database and uploaded documents are stored in `data/`. Restarting the server keeps these records. Do not put `data/` or your real `.env` file in GitHub. Back up the entire data directory when the server is stopped; if backing up while running, use a proper SQLite backup method rather than copying only the main database file.

Browser account creation is disabled in every mode. The first Admin is provisioned locally or through private server environment variables; all subsequent account creation requires an authenticated Admin. Passwords are hashed with scrypt. Sessions use HttpOnly cookies and are invalidated when the password changes or access is disabled.

## Rebuild the Flutter screens

The Flutter source is in `frontend/`. To change the interface, install Flutter, then run:

```powershell
cd frontend
flutter pub upgrade
flutter analyze
flutter test --dart-define=API_URL=http://localhost
cd ..
npm run build
```

The build helper finds `flutter` on PATH. If needed, set `FLUTTER_BIN` to the full path to `flutter.bat` on Windows or `flutter` on Linux/macOS. Building updates `public/pos`. This command does not deploy anything.

## Upload it yourself later

Upload this standalone app folder to your own private repository or Node.js host. It includes the compiled Flutter assets and requires no build on the host. The start command is **`npm start`**. Use a host with a persistent disk and HTTPS; this version stores the database and files on disk and is not designed for an ephemeral serverless filesystem.

Configure the following private environment variables on the host:

```text
NODE_ENV=production
HOST=0.0.0.0
PUBLIC_URL=https://your-own-domain.example
DATA_DIR=/path/to/persistent/storage
ADMIN_NAME=Your name
ADMIN_USERNAME=admin
ADMIN_PASSWORD=your-private-password-with-at-least-12-characters
```

`PORT` is read from the host environment, or defaults to 3000. On an empty production database, the administrator is created from those private environment variables. After it exists, the bootstrap password can be removed from the host environment. It does not overwrite an existing account on restart. To reset staff passwords later, use Administration.

Run one application instance per SQLite data directory. Multiple branches and devices connect to that same server and share the database. Test printers and configure employee access before live branch use. K-NET and card entries currently record payments received externally; no payment terminal, booking system or inventory system is connected. Voucher/package balances, offline sales synchronization and shift reconciliation remain outside this first version.

The original 446 catalogue items came from the supplied Excel price list. Desktop screens follow the old POS layout. Phone and tablet layouts adapt to the available space. Prices are stored as integer fils and reports use Kuwait business dates.
