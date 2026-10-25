# Core Banking & Transaction Management System

React banking portals and a FastAPI backend for the BCSE302P PostgreSQL banking
project, with the original Streamlit interface also available.

## FastAPI backend

With the existing PostgreSQL container running, start the API from the project root:

```powershell
uv sync
uv run uvicorn backend.main:app --reload
```

API: `http://127.0.0.1:8000`. Interactive docs: `http://127.0.0.1:8000/docs`.
The complete workflow coverage, transaction design, schema decisions, and
isolated integration-test instructions are documented in `backend/README.md`.
Database configuration is in `backend/database.py`; optionally override the
default local connection with the `DATABASE_URL` environment variable.

`POST /api/login` accepts `{"id": 1, "role": "Customer"}` or role `Admin`.
Customer IDs must exist; Admin identities are simulated. Login does not issue
tokens or enforce route permissions. Wildcard CORS is enabled for local React
development without credentialed cookies.

| Method | Path | Request body |
| --- | --- | --- |
| GET | `/api/health` | — |
| POST | `/api/login` | `id`, `role` |
| GET | `/api/customer/{customer_id}/passbook` | — |
| GET | `/api/customer/{customer_id}/net-worth` | — |
| POST | `/api/transaction/transfer` | `sender`, `receiver`, `amount`, `mode`, optional `remarks` |
| POST | `/api/transaction/emi` | `customer_id`, `loan_id`, `account_no` |
| GET | `/api/admin/summary` | — |
| GET | `/api/admin/audit-log` | — |
| POST | `/api/admin/batch/interest` | — |

Send monetary values as decimal strings, e.g. `"amount": "1000.00"`; numeric
JSON inputs are also accepted. Monetary responses are exact decimal strings;
database column names are lowercase. Passbook uses an Account join because the
existing view has no CustomerID column. Business failures return HTTP 400 with
`success: false`, `detail: "Transaction Failed: ..."`, and PostgreSQL `sqlstate`.
Invalid request schemas return 422, missing customers 404, transaction conflicts
409, and unavailable database connections 503. Reads and directly committing
procedures use isolated autocommit connections; multi-statement workflows use
one atomic transaction with rollback on failure.

## React frontend (Vite + Tailwind v4)

Start the FastAPI backend above, then in a second terminal:

```powershell
cd frontend
npm install
npm run dev
```

Open the Vite local URL (normally `http://localhost:5173`). Customer ID `1` or
`11` opens customer banking; Admin ID `1` opens the staff dashboard. See
`frontend/README.md` for configuration, routes, and build instructions.

## Original Streamlit frontend

Start the existing `banking-postgres` container, then run from this directory:

```powershell
uv sync
uv run streamlit run app.py
```

Open the local URL printed by Streamlit. Use **Role Selector** to switch between
the customer and staff portals. Try Customer ID `1` (accounts `100001`, `100002`)
or identify the same customer by Account number `100001`.

The application uses the existing `banking_db` on `localhost:5432` with the
provided local lab credentials. Database scripts `01` through `06` must already
be installed. See `PROJECT_SPEC.md` for the backend schema and setup details.
The role selector simulates a lab login; the app connects using `postgres`.

Customer transfers and EMI payments commit real changes. Batch buttons execute
the stored procedures, and the audit panel refreshes every ten seconds. Failed
operations display `Transaction Failed:` with the database error. Each database
action uses its own autocommit connection, including the transfer procedure
that explicitly commits. Successful actions refresh displayed balances and logs.
