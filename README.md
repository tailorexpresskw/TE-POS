# Tailor Express POS

Standalone Flutter Web POS with Admin, Supervisor, Branch Manager, Reception and Tailor dashboards. Staff sign in with a username and password. The Node.js server stores invoices, tracking history and documents locally.

First-time administrator setup: `Setup-Admin.cmd`. Then run `Start-POS.cmd` and open http://localhost:3000. Only Admin can create staff users and branches. Supervisors oversee one or more assigned branches. Aventura is retired from branch selection; its historical records remain stored.

See [Local setup and your own deployment](docs/LOCAL-SETUP.md). All current work is local; publishing is under your control.

The POS can be installed as a web app and includes a staff notification inbox and optional device alerts. See [installation, notifications and future Android/iOS apps](docs/APP-AND-NOTIFICATIONS.md).

The project folders are:

- `frontend/lib/` ? Flutter screens and workflows; `frontend/web/` contains browser assets.
- `server/` ? local server, login, SQLite storage and backend tests.
- `lib/` ? invoice, tracking and pricing rules, plus the imported catalogue.
- `db/` and `drizzle/` ? database schema and migrations. Keep every migration to support existing databases.
- `public/pos/` ? the compiled app served to browsers.
- `scripts/` ? build, package, price-list import and browser checks.
- `data/` ? private accounts, invoices and documents; excluded from Git and release packages.

To check backend changes, run `npm test` and `npm run typecheck`. For Flutter, run `flutter analyze` and `flutter test --dart-define=API_URL=http://localhost` inside `frontend/`. Run `npm run build` after changing Flutter screens. A source checkout needs `npm ci --omit=dev` for the Web Push runtime dependency, or `npm ci` to include development tools. The standalone ZIP includes runtime dependencies already.
