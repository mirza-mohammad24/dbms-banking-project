import { useCallback, useState } from "react";
import { useSearchParams } from "react-router-dom";
import {
  Building2,
  Check,
  CirclePlus,
  CreditCard,
  Database,
  Eye,
  Landmark,
  LayoutDashboard,
  RefreshCw,
  UsersRound,
  Wallet,
  X,
} from "lucide-react";
import DashboardLayout from "../components/DashboardLayout";
import Toast from "../components/Toast";
import Customer360 from "../components/Customer360";
import AdminAnalytics from "../components/AdminAnalytics";
import {
  Badge,
  DataTable,
  EMIQuote,
  Modal,
  Panel,
  ResourceState,
  WorkflowForm,
  accountColumns,
  buttonClass,
  choices,
  fdColumns,
  inputClass,
  loanColumns,
  moneyColumn,
  option,
  secondaryClass,
} from "../components/BankingUI";
import {
  accountOptions,
  accountStates,
  branchOptions,
  customerFields,
  customerOptions,
  nullable,
  number,
  select,
  text,
} from "../lib/forms";
import { currency, dateTime } from "../lib/api";
import { useDebounced, useResource, useWorkflow } from "../lib/hooks";

const tabs = [
  {
    id: "analytics",
    label: "Executive analytics & views",
    icon: LayoutDashboard,
    description:
      "The bank-wide picture, backed by live relational views and independent product totals.",
  },
  {
    id: "customers",
    label: "Customer 360° & KYC",
    icon: UsersRound,
    description:
      "Discover exact account ownership, inspect complete portfolios, and verify customer identities.",
  },
  {
    id: "accounts",
    label: "Account management desk",
    icon: Landmark,
    description:
      "Open accounts, inspect balances, and control whether each account can transact.",
  },
  {
    id: "loans",
    label: "Loan origination & portfolio",
    icon: CreditCard,
    description:
      "Sanction loans with live PostgreSQL EMI previews and optional account disbursement.",
  },
  {
    id: "fds",
    label: "Fixed deposit book",
    icon: Wallet,
    description:
      "All deposit commitments, owners, maturity values, and lifecycle states.",
  },
  {
    id: "infrastructure",
    label: "Branches, staff & directories",
    icon: Building2,
    description:
      "Manage the branch network and the normalized directories behind it.",
  },
  {
    id: "batch",
    label: "Batch cursors & audit trail",
    icon: Database,
    description:
      "Run PL/pgSQL cursor jobs and see the resulting account and deposit audit events.",
  },
];

export default function AdminDashboard() {
  const flow = useWorkflow();
  const [params, setParams] = useSearchParams();
  const tab = tabs.some((t) => t.id === params.get("tab"))
    ? params.get("tab")
    : "analytics";
  const [modal, setModal] = useState(null);
  const close = useCallback(() => setModal(null), []);
  const [search, setSearch] = useState("");
  const debouncedSearch = useDebounced(search);
  const [kyc, setKyc] = useState("");
  const [fdStatus, setFdStatus] = useState("");
  const [accountStatus, setAccountStatus] = useState("");
  const [infraTab, setInfraTab] = useState("branches");
  const [auditFilters, setAuditFilters] = useState({
    table_name: "",
    action_type: "",
  });
  const dashboard = useResource("/api/admin/dashboard", flow.revision);
  const directory = useResource(
    "/api/directory/customers-preview",
    flow.revision,
  );
  const master = useResource(
    `/api/admin/customers-master?${new URLSearchParams({ search: debouncedSearch, kyc_status: kyc })}`,
    flow.revision,
  );
  const accounts = useResource("/api/admin/accounts", flow.revision);
  const loans = useResource("/api/admin/loans", flow.revision);
  const fds = useResource(
    `/api/admin/fixed-deposits?${new URLSearchParams({ status: fdStatus })}`,
    flow.revision,
  );
  const infrastructure = useResource(
    "/api/admin/infrastructure",
    flow.revision,
  );
  const audits = useResource(
    tab === "batch"
      ? `/api/admin/audit-log?${new URLSearchParams(auditFilters)}`
      : null,
    flow.revision,
    10000,
  );
  const catalog = useResource(
    tab === "batch" ? "/api/admin/programmability" : null,
    flow.revision,
  );
  const customers = directory.data || [];
  const infra = infrastructure.data || {
    branches: [],
    employees: [],
    postal_directory: [],
    bank_directory: [],
  };
  const allAccounts = accounts.data || [];
  async function submit(path, payload, method = "post") {
    const result = await flow.run(path, payload, method);
    if (result) close();
    return result;
  }
  const activeResource = {
    analytics: dashboard,
    customers: master,
    accounts,
    loans,
    fds,
    infrastructure,
    batch: audits,
  }[tab];
  const postalFirst = infra.postal_directory[0];

  const branchFields = [
    text("branch_name", "Branch name", { maxLength: 100 }),
    text("address", "Branch address", { maxLength: 200 }),
    select(
      "pincode_choice",
      "Postal directory",
      [
        ...infra.postal_directory.map((p) =>
          option(p.pincode, `${p.pincode} · ${p.city}, ${p.state}`),
        ),
        option("__new__", "+ Register a new pincode"),
      ],
      {
        onChange: (value) => {
          const p = infra.postal_directory.find((p) => p.pincode === value);
          return { city: p?.city || "", state: p?.state || "" };
        },
      },
    ),
    text("new_pincode", "New pincode", {
      when: (v) => v.pincode_choice === "__new__",
      maxLength: 10,
    }),
    text("city", "City", {
      maxLength: 50,
      disabled: (v) => v.pincode_choice !== "__new__",
    }),
    text("state", "State", {
      maxLength: 50,
      disabled: (v) => v.pincode_choice !== "__new__",
    }),
    select(
      "ifsc_choice",
      "Bank / IFSC directory",
      [
        ...infra.bank_directory.map((b) =>
          option(b.ifsc_code, `${b.ifsc_code} · ${b.bankname}`),
        ),
        option("__new__", "+ Register a new IFSC"),
      ],
      {
        onChange: (value) => ({
          bank_name:
            infra.bank_directory.find((b) => b.ifsc_code === value)?.bankname ||
            "",
        }),
      },
    ),
    text("new_ifsc", "New IFSC", {
      when: (v) => v.ifsc_choice === "__new__",
      maxLength: 15,
      pattern: "[A-Z0-9]+",
    }),
    text("bank_name", "Bank name", {
      maxLength: 100,
      disabled: (v) => v.ifsc_choice !== "__new__",
    }),
    text("contact_phone", "Branch phone", { maxLength: 15 }),
  ];

  return (
    <DashboardLayout
      tabs={tabs}
      activeTab={tab}
      onSelect={(value) => setParams({ tab: value })}
      revision={flow.revision}
      connected={Boolean(dashboard.data) && !activeResource.error}
    >
      <Toast toast={flow.toast} onClose={flow.closeToast} />
      <div className="flex flex-wrap items-center justify-between gap-3">
        <span className="rounded-full border border-blue-100 dark:border-blue-800 bg-blue-50 dark:bg-blue-950/40 px-3 py-1.5 text-[10px] font-semibold text-blue-700 dark:text-blue-300">
          Bank official · all-branch demonstration access
        </span>
        <button
          className={secondaryClass}
          disabled={flow.busy}
          onClick={flow.refresh}
        >
          <RefreshCw className="size-3.5" />
          Refresh records
        </button>
      </div>
      <ResourceState resource={activeResource} />
      {tab === "analytics" && <AdminAnalytics data={dashboard.data} />}

      {tab === "customers" && (
        <Panel
          title="Customer ownership directory"
          subtitle="The exact account list, product counts, and balances for every customer."
          action={
            <button
              className={buttonClass}
              onClick={() => setModal({ kind: "customer" })}
            >
              <CirclePlus className="size-4" />
              Onboard customer
            </button>
          }
        >
          <div className="grid gap-3 p-5 sm:grid-cols-[1fr_220px]">
            <input
              aria-label="Search customers by name PAN or account"
              className={inputClass}
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search customer, PAN, ID or account number…"
            />
            <select
              aria-label="Filter customer KYC"
              className={inputClass}
              value={kyc}
              onChange={(e) => setKyc(e.target.value)}
            >
              <option value="">All KYC statuses</option>
              {["Pending", "Approved", "Rejected"].map((status) => (
                <option key={status}>{status}</option>
              ))}
            </select>
          </div>
          <DataTable
            searchable={false}
            rows={master.data || []}
            columns={[
              {
                key: "customerid",
                label: "Customer",
                render: (c) => (
                  <div>
                    <p className="font-semibold text-slate-800 dark:text-slate-200">
                      {c.firstname} {c.lastname}
                    </p>
                    <p className="mt-1 text-[10px] text-slate-400">
                      #{c.customerid} · {c.pan_number}
                    </p>
                  </div>
                ),
              },
              {
                key: "accounts",
                label: "Exact account ownership",
                render: (c) => (
                  <div className="flex min-w-44 flex-wrap gap-1.5">
                    {c.accounts.length ? (
                      c.accounts.map((a) => (
                        <span
                          key={a.accountno}
                          className="rounded-md border border-slate-200 dark:border-slate-700 bg-slate-50 dark:bg-slate-950 px-2 py-1 text-[10px]"
                          title={`${a.type} · ${currency(a.balance)} · ${a.status}`}
                        >
                          #{a.accountno}{" "}
                          <span className="text-slate-400">{a.type}</span>
                        </span>
                      ))
                    ) : (
                      <span className="text-slate-400">No accounts</span>
                    )}
                  </div>
                ),
              },
              moneyColumn("totalbalance", "Total balance"),
              {
                key: "products",
                label: "Products",
                render: (c) => (
                  <div className="whitespace-nowrap text-[10px]">
                    {c.activeloans} active loans
                    <br />
                    {c.activefds} active FDs
                  </div>
                ),
              },
              {
                key: "kyc_status",
                label: "KYC",
                render: (c) => <Badge value={c.kyc_status} />,
              },
              {
                key: "actions",
                label: "Review",
                render: (c) => (
                  <div className="flex items-center gap-1">
                    <button
                      className="whitespace-nowrap rounded-lg border border-slate-200 dark:border-slate-700 px-2.5 py-1.5 text-[10px] font-medium hover:bg-slate-50 dark:hover:bg-slate-950"
                      onClick={() =>
                        setModal({ kind: "inspect", id: c.customerid })
                      }
                    >
                      <Eye className="mr-1 inline size-3" />
                      Inspect 360°
                    </button>
                    <button
                      title="Approve KYC"
                      aria-label={`Approve KYC for customer ${c.customerid}`}
                      disabled={flow.busy}
                      onClick={() =>
                        flow.run(
                          `/api/admin/customers/${c.customerid}/kyc`,
                          { kyc_status: "Approved" },
                          "patch",
                        )
                      }
                      className="rounded-lg p-2 text-emerald-600 dark:text-emerald-400 hover:bg-emerald-50 dark:hover:bg-emerald-950/40"
                    >
                      <Check className="size-4" />
                    </button>
                    <button
                      title="Reject KYC"
                      aria-label={`Reject KYC for customer ${c.customerid}`}
                      disabled={flow.busy}
                      onClick={() =>
                        flow.run(
                          `/api/admin/customers/${c.customerid}/kyc`,
                          { kyc_status: "Rejected" },
                          "patch",
                        )
                      }
                      className="rounded-lg p-2 text-rose-500 dark:text-rose-400 hover:bg-rose-50 dark:hover:bg-rose-950/40"
                    >
                      <X className="size-4" />
                    </button>
                  </div>
                ),
              },
            ]}
          />
        </Panel>
      )}

      {tab === "accounts" && (
        <Panel
          title="Master account register"
          subtitle="Change status here, switch to the owner, and verify the database blocks frozen-account transactions."
          action={
            <button
              className={buttonClass}
              onClick={() => setModal({ kind: "account" })}
            >
              <CirclePlus className="size-4" />
              Open account
            </button>
          }
        >
          <div className="p-5 pb-0">
            <select
              aria-label="Filter accounts by status"
              className={`${inputClass} max-w-xs`}
              value={accountStatus}
              onChange={(e) => setAccountStatus(e.target.value)}
            >
              <option value="">All statuses</option>
              {accountStates.map((s) => (
                <option key={s}>{s}</option>
              ))}
            </select>
          </div>
          <DataTable
            rows={allAccounts.filter(
              (a) => !accountStatus || a.status === accountStatus,
            )}
            columns={[
              ...accountColumns.filter((c) => c.key !== "status"),
              {
                key: "status",
                label: "Status control",
                render: (a) => (
                  <select
                    aria-label={`Status of account ${a.accountno}`}
                    className="rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 px-2 py-2 text-[10px]"
                    value={a.status}
                    disabled={flow.busy}
                    onChange={(e) =>
                      flow.run(
                        `/api/admin/accounts/${a.accountno}/status`,
                        { status: e.target.value },
                        "patch",
                      )
                    }
                  >
                    {accountStates.map((s) => (
                      <option key={s}>{s}</option>
                    ))}
                  </select>
                ),
              },
            ]}
          />
        </Panel>
      )}

      {tab === "loans" && (
        <Panel
          title="Loan origination & portfolio"
          subtitle="Principal, EMI, outstanding liability and status are read directly from Loan."
          action={
            <button
              className={buttonClass}
              onClick={() => setModal({ kind: "loan" })}
            >
              <CirclePlus className="size-4" />
              Sanction loan
            </button>
          }
        >
          <DataTable
            rows={loans.data || []}
            columns={[
              ...loanColumns,
              { key: "issuedate", label: "Issue date" },
            ]}
          />
        </Panel>
      )}

      {tab === "fds" && (
        <Panel
          title="Bank-wide fixed deposit book"
          subtitle="PostgreSQL-generated maturity values for every customer."
          action={
            <select
              aria-label="Filter fixed deposit status"
              className={`${inputClass} max-w-44`}
              value={fdStatus}
              onChange={(e) => setFdStatus(e.target.value)}
            >
              <option value="">All FD statuses</option>
              {["Active", "Matured", "Closed"].map((s) => (
                <option key={s}>{s}</option>
              ))}
            </select>
          }
        >
          <DataTable rows={fds.data || []} columns={fdColumns} />
        </Panel>
      )}

      {tab === "infrastructure" && (
        <>
          <div className="flex flex-wrap gap-2">
            {[
              ["branches", "Branch network"],
              ["employees", "Bank officials"],
              ["postal_directory", "Postal directory"],
              ["bank_directory", "Bank / IFSC directory"],
            ].map(([value, label]) => (
              <button
                key={value}
                onClick={() => setInfraTab(value)}
                className={infraTab === value ? buttonClass : secondaryClass}
              >
                {label}
              </button>
            ))}
          </div>
          {infraTab === "branches" && (
            <Panel
              title="Branches & normalized location lookups"
              subtitle="Each branch references one postal directory entry."
              action={
                <button
                  className={buttonClass}
                  onClick={() => setModal({ kind: "branch" })}
                >
                  <CirclePlus className="size-4" />
                  Add branch
                </button>
              }
            >
              <DataTable
                rows={infra.branches}
                columns={[
                  { key: "branchid", label: "ID" },
                  { key: "branchname", label: "Branch" },
                  { key: "address", label: "Address" },
                  { key: "pincode", label: "Pincode" },
                  { key: "city", label: "City" },
                  { key: "state", label: "State" },
                  { key: "ifsc_code", label: "IFSC" },
                  { key: "contactphone", label: "Phone" },
                ]}
              />
            </Panel>
          )}
          {infraTab === "employees" && (
            <Panel
              title="Bank official roster"
              subtitle="Employee-to-branch relationships drive official identity selection."
              action={
                <button
                  className={buttonClass}
                  onClick={() => setModal({ kind: "employee" })}
                >
                  <CirclePlus className="size-4" />
                  Add official
                </button>
              }
            >
              <DataTable
                rows={infra.employees}
                columns={[
                  { key: "employeeid", label: "ID" },
                  {
                    key: "name",
                    label: "Official",
                    render: (e) => `${e.firstname} ${e.lastname}`,
                  },
                  { key: "role", label: "Role" },
                  { key: "branchname", label: "Branch" },
                  { key: "email", label: "Email" },
                  moneyColumn("salary", "Salary"),
                  { key: "hiredate", label: "Hired" },
                ]}
              />
            </Panel>
          )}
          {infraTab === "postal_directory" && (
            <Panel
              title="Postal directory · Pincode → City, State"
              action={
                <button
                  className={buttonClass}
                  onClick={() => setModal({ kind: "postal" })}
                >
                  <CirclePlus className="size-4" />
                  Add pincode
                </button>
              }
            >
              <DataTable
                rows={infra.postal_directory}
                columns={[
                  { key: "pincode", label: "Pincode" },
                  { key: "city", label: "City" },
                  { key: "state", label: "State" },
                ]}
              />
            </Panel>
          )}
          {infraTab === "bank_directory" && (
            <Panel
              title="Bank directory · IFSC → BankName"
              action={
                <button
                  className={buttonClass}
                  onClick={() => setModal({ kind: "bank" })}
                >
                  <CirclePlus className="size-4" />
                  Add bank / IFSC
                </button>
              }
            >
              <DataTable
                rows={infra.bank_directory}
                columns={[
                  { key: "ifsc_code", label: "IFSC code" },
                  { key: "bankname", label: "Bank name" },
                ]}
              />
            </Panel>
          )}
        </>
      )}

      {tab === "batch" && (
        <>
          <div className="grid gap-5 xl:grid-cols-2">
            {[
              [
                "interest",
                "Monthly savings interest",
                "Credit one rounded monthly interest amount to each eligible Active Savings account. Already posted accounts are skipped for the current month.",
                "sp_batch_credit_savings_interest",
                "Run savings interest batch",
              ],
              [
                "mature-fds",
                "FD maturity settlement",
                "Settle due Active FDs into each owner’s primary Active Savings account. Each settlement creates a transaction and audit events.",
                "sp_batch_mature_fixed_deposits",
                "Run FD maturity batch",
              ],
            ].map(([route, title, description, procedure, label]) => (
              <Panel
                key={route}
                title={title}
                subtitle="PL/pgSQL cursor control center"
              >
                <div className="p-6">
                  <div className="mb-4 inline-flex rounded-xl bg-blue-50 dark:bg-blue-950/40 p-3 text-blue-600 dark:text-blue-400">
                    <Database className="size-6" />
                  </div>
                  <p className="text-xs leading-7 text-slate-500 dark:text-slate-400">
                    {description}
                  </p>
                  <p className="my-4 rounded-lg bg-slate-50 dark:bg-slate-950 p-3 font-mono text-[10px] break-all text-slate-400">
                    CALL {procedure}()
                  </p>
                  <button
                    className={buttonClass}
                    disabled={flow.busy}
                    onClick={() => flow.run(`/api/admin/batch/${route}`)}
                  >
                    <RefreshCw
                      className={`size-4 ${flow.busy ? "animate-spin" : ""}`}
                    />
                    {flow.busy ? "Processing…" : label}
                  </button>
                </div>
              </Panel>
            ))}
          </div>
          <Panel
            title="Live trigger audit trail"
            subtitle="Latest 100 rows · auto-refresh every 10 seconds while this tab is visible."
          >
            <div className="grid gap-3 p-5 sm:grid-cols-2">
              <select
                aria-label="Audit table filter"
                className={inputClass}
                value={auditFilters.table_name}
                onChange={(e) =>
                  setAuditFilters((v) => ({ ...v, table_name: e.target.value }))
                }
              >
                <option value="">All tables</option>
                {Object.keys(dashboard.data?.table_counts || {}).map((t) => (
                  <option key={t}>{t}</option>
                ))}
              </select>
              <select
                aria-label="Audit action filter"
                className={inputClass}
                value={auditFilters.action_type}
                onChange={(e) =>
                  setAuditFilters((v) => ({
                    ...v,
                    action_type: e.target.value,
                  }))
                }
              >
                <option value="">All actions</option>
                {[
                  ...new Set([
                    "BALANCE_UPDATE",
                    "FD_MATURED",
                    "SEED",
                    ...(audits.data || []).map((a) => a.actiontype),
                  ]),
                ].map((a) => (
                  <option key={a}>{a}</option>
                ))}
              </select>
            </div>
            <DataTable
              maxHeight
              pageSize={20}
              rows={audits.data || []}
              columns={[
                { key: "logid", label: "Log ID" },
                { key: "tablename", label: "Table" },
                { key: "recordid", label: "Record" },
                {
                  key: "actiontype",
                  label: "Action",
                  render: (a) => <Badge value={a.actiontype} />,
                },
                { key: "description", label: "Description" },
                {
                  key: "logdate",
                  label: "Date",
                  render: (a) => (
                    <span className="whitespace-nowrap">
                      {dateTime(a.logdate)}
                    </span>
                  ),
                },
              ]}
            />
          </Panel>
          <Panel
            title="Installed database programmability"
            subtitle="Live catalog evidence of the views, procedures, functions and triggers used by the portals."
          >
            <ResourceState resource={catalog} />
            {catalog.data && (
              <div className="space-y-5 p-5">
                <div className="grid gap-4 md:grid-cols-2">
                  <div className="rounded-xl bg-slate-50 dark:bg-slate-950 p-4">
                    <h3 className="mb-3 text-xs font-semibold">Views</h3>
                    {catalog.data.views.map((v) => (
                      <p
                        key={v.viewname}
                        className="py-1 font-mono text-[10px] text-slate-500 dark:text-slate-400"
                      >
                        {v.viewname}
                      </p>
                    ))}
                  </div>
                  <div className="rounded-xl bg-slate-50 dark:bg-slate-950 p-4">
                    <h3 className="mb-3 text-xs font-semibold">
                      Functions & stored procedures
                    </h3>
                    {catalog.data.routines
                      .filter(
                        (r) => r.proname.startsWith("fn_") || r.prokind === "p",
                      )
                      .map((r) => (
                        <p
                          key={r.proname}
                          className="py-1 font-mono text-[10px] text-slate-500 dark:text-slate-400"
                        >
                          {r.proname}
                        </p>
                      ))}
                  </div>
                </div>
                {catalog.data.triggers.map((t) => (
                  <div
                    key={t.tgname}
                    className="rounded-xl border border-slate-200 dark:border-slate-700 p-4"
                  >
                    <p className="text-xs font-semibold">
                      {t.tgname}{" "}
                      <span className="font-normal text-slate-400">
                        on {t.table_name}
                      </span>
                    </p>
                    <pre className="mt-2 overflow-auto font-mono text-[10px] leading-6 whitespace-pre-wrap break-words text-slate-400">
                      {t.definition}
                    </pre>
                  </div>
                ))}
              </div>
            )}
          </Panel>
        </>
      )}

      {modal?.kind === "inspect" && (
        <Modal
          wide
          title={`Customer 360° · #${modal.id}`}
          subtitle="Complete ownership and product relationships from the relational database."
          onClose={close}
        >
          <Customer360 customerId={modal.id} revision={flow.revision} />
        </Modal>
      )}
      {modal?.kind === "customer" && (
        <Modal
          title="Onboard a new customer"
          subtitle="Unique phone, email and PAN constraints are enforced by PostgreSQL."
          onClose={close}
        >
          <WorkflowForm
            fields={customerFields}
            busy={flow.busy}
            submitLabel="Create customer"
            onSubmit={(values) => submit("/api/admin/customers", values)}
          />
        </Modal>
      )}
      {modal?.kind === "account" && (
        <Modal
          title="Open a bank account"
          subtitle="The owner, servicing branch and opening deposit are recorded together."
          onClose={close}
        >
          <WorkflowForm
            busy={flow.busy}
            submitLabel="Open account"
            initial={{
              account_type: "Savings",
              balance: "1000.00",
              interest_rate: "3.50",
            }}
            fields={[
              select(
                "customer_id",
                "Customer / account owner",
                customerOptions(customers),
                { wide: true },
              ),
              select(
                "branch_id",
                "Servicing branch",
                branchOptions(infra.branches),
                { wide: true },
              ),
              select(
                "account_type",
                "Account type",
                choices(["Savings", "Current", "Salary"]),
                {
                  onChange: (value) => ({
                    interest_rate: value === "Current" ? "0.00" : "3.50",
                  }),
                },
              ),
              number("balance", "Initial deposit (INR)", { min: 0 }),
              number("interest_rate", "Annual interest %", {
                min: 0,
                max: 999,
              }),
            ]}
            onSubmit={(values) => submit("/api/admin/accounts", values)}
          />
        </Modal>
      )}
      {modal?.kind === "loan" && (
        <Modal
          title="Sanction a new loan"
          subtitle="Generated EMI and optional disbursement share one transaction."
          onClose={close}
        >
          <WorkflowForm
            busy={flow.busy}
            submitLabel="Sanction loan"
            initial={{
              loan_type: "Personal",
              principal_amount: "100000",
              interest_rate: "10.50",
              tenure_months: "36",
            }}
            fields={[
              select("customer_id", "Borrower", customerOptions(customers), {
                wide: true,
                onChange: (value) => ({
                  account_no: "",
                  branch_id: String(
                    allAccounts.find((a) => String(a.customerid) === value)
                      ?.branchid || "",
                  ),
                }),
              }),
              select(
                "branch_id",
                "Issuing branch",
                branchOptions(infra.branches),
                { wide: true },
              ),
              select(
                "loan_type",
                "Purpose",
                choices(["Home", "Personal", "Auto", "Education", "Business"]),
              ),
              number("principal_amount", "Principal amount (INR)"),
              number("interest_rate", "Interest rate %", {
                min: 0.01,
                max: 999,
              }),
              number("tenure_months", "Tenure in months", {
                min: 1,
                max: 600,
                step: 1,
              }),
              select(
                "account_no",
                "Optional disbursement account",
                (values) =>
                  accountOptions(
                    allAccounts.filter(
                      (a) =>
                        String(a.customerid) === String(values.customer_id),
                    ),
                  ),
                {
                  required: false,
                  wide: true,
                  helper:
                    "Leave blank to sanction without crediting principal. Only the borrower’s accounts are listed.",
                },
              ),
            ]}
            preview={(values) => <EMIQuote values={values} />}
            onSubmit={(values) => submit("/api/admin/loans", nullable(values))}
          />
        </Modal>
      )}
      {modal?.kind === "branch" && (
        <Modal
          title="Add a branch"
          subtitle="Existing shared postal and bank facts cannot be silently overwritten."
          onClose={close}
        >
          <WorkflowForm
            busy={flow.busy}
            submitLabel="Create branch"
            fields={branchFields}
            initial={{
              pincode_choice: postalFirst?.pincode || "__new__",
              city: postalFirst?.city || "",
              state: postalFirst?.state || "",
              ifsc_choice: "__new__",
              bank_name: "",
            }}
            onSubmit={(v) =>
              submit("/api/admin/branches", {
                branch_name: v.branch_name,
                address: v.address,
                pincode:
                  v.pincode_choice === "__new__"
                    ? v.new_pincode
                    : v.pincode_choice,
                city: v.city,
                state: v.state,
                ifsc_code:
                  v.ifsc_choice === "__new__" ? v.new_ifsc : v.ifsc_choice,
                bank_name: v.bank_name,
                contact_phone: v.contact_phone,
              })
            }
          />
        </Modal>
      )}
      {modal?.kind === "employee" && (
        <Modal title="Add a bank official" onClose={close}>
          <WorkflowForm
            busy={flow.busy}
            submitLabel="Add official"
            initial={{ salary: "50000", hire_date: infra.today }}
            fields={[
              text("first_name", "First name", { maxLength: 50 }),
              text("last_name", "Last name", { maxLength: 50 }),
              select(
                "branch_id",
                "Assigned branch",
                branchOptions(infra.branches),
                { wide: true },
              ),
              text("email", "Email", { type: "email", maxLength: 100 }),
              text("role", "Role / designation", {
                maxLength: 30,
                placeholder: "Branch Manager",
              }),
              number("salary", "Monthly salary (INR)"),
              text("hire_date", "Hire date", { type: "date" }),
            ]}
            onSubmit={(values) => submit("/api/admin/employees", values)}
          />
        </Modal>
      )}
      {modal?.kind === "postal" && (
        <Modal title="Register a pincode" onClose={close}>
          <WorkflowForm
            busy={flow.busy}
            submitLabel="Save postal entry"
            fields={[
              text("pincode", "Pincode", { maxLength: 10 }),
              text("city", "City", { maxLength: 50 }),
              text("state", "State", { maxLength: 50 }),
            ]}
            onSubmit={(values) => submit("/api/admin/postal-directory", values)}
          />
        </Modal>
      )}
      {modal?.kind === "bank" && (
        <Modal title="Register a bank IFSC" onClose={close}>
          <WorkflowForm
            busy={flow.busy}
            submitLabel="Save IFSC entry"
            fields={[
              text("ifsc_code", "IFSC code", {
                maxLength: 15,
                pattern: "[A-Z0-9]+",
              }),
              text("bank_name", "Bank name", { maxLength: 100 }),
            ]}
            onSubmit={(values) => submit("/api/admin/bank-directory", values)}
          />
        </Modal>
      )}
    </DashboardLayout>
  );
}
