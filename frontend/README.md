# CoreBank React frontend

React + Vite + Tailwind CSS v4, connected to the existing FastAPI/PostgreSQL backend.

```powershell
npm install
npm run dev
```

Start FastAPI separately from the repository root with
`uv run uvicorn backend.main:app --reload`.
Open the Vite URL printed in the terminal (normally `http://localhost:5173`).

- `/`: simulated login. Use Customer ID `1` or `11`, or Admin ID `1`.
- `/customer/dashboard`: six sections selected by `?tab=overview`, `accounts`,
  `transfers`, `loans`, `fds`, and `profile`.
- `/admin/dashboard`: seven sections selected by `?tab=analytics`, `customers`,
  `accounts`, `loans`, `fds`, `infrastructure`, and `batch`.

The login page searches real customers by name, PAN, customer ID, or owned account
number and shows account lists/balances. It also accepts a direct CustomerID or
AccountNo and real Employee profiles. The top navigation switcher can jump
between customers, bank officials, and portals without guessing identifiers.

Customer workflows include account cards, filtered statements, deposit/withdraw
dialogs, saved-beneficiary management, internal/external transfers, EMI payments
with refreshed repayment history, funded FDs with maturity estimates, and KYC
records. Official workflows include complete customer 360 dialogs, KYC actions,
opening/freezing accounts, loan origination with database EMI preview, FD book,
branch/staff/directory forms, two batch controls, all three views, and a filtered
live audit/programmability panel. Lucide supplies the banking icons.

Login validates customers with `/api/login`, then stores the returned identity,
role, and ID in localStorage. Route guards are navigation conveniences for this
simulated-login development app; they are not server-side authorization.
Transfer and batch actions commit real database changes. API error details are
displayed in dismissible notifications. Transfers refresh net worth and history;
batch processing refreshes branch totals and audits. Audit records poll every ten
seconds while the page is visible. Pending actions are disabled to limit duplicates.

Axios defaults to `http://localhost:8000`. To change it, copy `.env.example` to
`.env.local`, adjust `VITE_API_URL`, and restart Vite. All amounts are displayed
as INR; transfer amounts are sent as decimal strings.

Use the sun/moon button on the login card or dashboard header to switch between
light and dark mode. The initial theme follows your operating system; an explicit
choice is saved in localStorage and synchronized across open tabs. Tables, dialogs,
form controls, notifications, and chart palettes all support both themes.

Tailwind v4 uses `@tailwindcss/vite` in `vite.config.js` and the single import in
`src/index.css`, plus a class-based dark variant. No legacy Tailwind or PostCSS configuration is needed.
Build a production bundle with `npm run build`. Configure SPA history fallback
to `index.html` when deploying so dashboard URLs work on direct navigation.
