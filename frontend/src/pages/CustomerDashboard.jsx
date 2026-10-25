import { useCallback, useState } from "react";
import { useSearchParams } from "react-router-dom";
import {
  Activity,
  ArrowDownToLine,
  ArrowUpFromLine,
  ArrowLeftRight,
  CirclePlus,
  CreditCard,
  Landmark,
  LayoutDashboard,
  ShieldCheck,
  Trash2,
  Wallet,
} from "lucide-react";
import {
  Bar,
  BarChart,
  Cell,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import DashboardLayout from "../components/DashboardLayout";
import Toast from "../components/Toast";
import {
  Badge,
  DataTable,
  Metrics,
  Modal,
  Panel,
  ResourceState,
  WorkflowForm,
  buttonClass,
  secondaryClass,
  inputClass,
  option,
  choices,
  moneyColumn,
  transactionColumns,
  fdColumns,
} from "../components/BankingUI";
import {
  accountOptions,
  beneficiaryFields,
  beneficiaryPayload,
  modes,
  number,
  plusDays,
  select,
  text,
} from "../lib/forms";
import { compactCurrency, currency, dateTime } from "../lib/api";
import { useResource, useWorkflow } from "../lib/hooks";
import { useSession } from "../lib/session";

const tabs = [
  {
    id: "overview",
    label: "Portfolio overview",
    icon: LayoutDashboard,
    description:
      "Your balances, investments, and obligations — connected in one picture.",
  },
  {
    id: "accounts",
    label: "My accounts & passbook",
    icon: Landmark,
    description:
      "Know every account you own. Explore statements, deposit funds, or make a withdrawal.",
  },
  {
    id: "transfers",
    label: "Transfers & beneficiaries",
    icon: ArrowLeftRight,
    description:
      "Move money with confidence and keep your trusted payees close.",
  },
  {
    id: "loans",
    label: "Loans & EMI center",
    icon: CreditCard,
    description:
      "Follow every loan from sanction to settlement. See repayments reflected immediately.",
  },
  {
    id: "fds",
    label: "Fixed deposit vault",
    icon: Wallet,
    description:
      "Turn savings into a plan with database-calculated maturity values.",
  },
  {
    id: "profile",
    label: "Profile & KYC details",
    icon: ShieldCheck,
    description: "Your complete customer identity and verification record.",
  },
];

function FDPreview({ values }) {
  const days =
    (new Date(values.end_date) - new Date(values.start_date)) / 86400000;
  const estimate =
    Number(values.amount) * (1 + (Number(values.interest_rate) * days) / 36500);
  return (
    <div className="rounded-xl border border-blue-100 dark:border-blue-800 bg-blue-50 dark:bg-blue-950/40 p-4">
      <p className="text-[10px] font-semibold text-blue-500 dark:text-blue-400 uppercase">
        Estimated maturity · {days > 0 ? days : "—"} days
      </p>
      <p className="mt-2 text-2xl font-semibold text-blue-900 dark:text-blue-300">
        {days > 0 && Number(values.amount) >= 1000 ? currency(estimate) : "—"}
      </p>
      <p className="mt-1 text-[10px] leading-5 text-blue-500 dark:text-blue-400">
        Actual-day simple interest. PostgreSQL generates the final stored value
        on opening.
      </p>
    </div>
  );
}

export default function CustomerDashboard() {
  const user = useSession();
  const flow = useWorkflow();
  const [params, setParams] = useSearchParams();
  const tab = tabs.some((t) => t.id === params.get("tab"))
    ? params.get("tab")
    : "overview";
  const [modal, setModal] = useState(null);
  const close = useCallback(() => setModal(null), []);
  const [filters, setFilters] = useState({
    account_no: "",
    txn_type: "",
    payment_mode: "",
  });
  const [selectedLoan, setSelectedLoan] = useState("");
  const [destination, setDestination] = useState("internal");
  const [fallbackToday] = useState(() => new Date().toISOString().slice(0, 10));
  const base = `/api/customer/${user.id}`;
  const overview = useResource(`${base}/overview`, flow.revision);
  const accounts = useResource(`${base}/accounts`, flow.revision);
  const loans = useResource(`${base}/loans`, flow.revision);
  const fds = useResource(`${base}/fixed-deposits`, flow.revision);
  const beneficiaries = useResource(`${base}/beneficiaries`, flow.revision);
  const lookups = useResource("/api/lookups", flow.revision);
  const transactionQuery = new URLSearchParams(
    Object.entries(tab === "accounts" ? filters : {}).filter(
      ([, value]) => value,
    ),
  );
  const transactions = useResource(
    `${base}/transactions?${transactionQuery}`,
    flow.revision,
  );
  const repayments = useResource(
    selectedLoan
      ? `/api/loans/${selectedLoan}/repayments?customer_id=${user.id}`
      : null,
    flow.revision,
  );
  const accountRows = accounts.data || [];
  const loanRows = loans.data || [];
  const fdRows = fds.data || [];
  const beneficiaryRows = beneficiaries.data || [];
  const totals = overview.data;
  const today = lookups.data?.today || fallbackToday;
  const funding = accountOptions(accountRows);
  const defaultAccount = String(
    accountRows.find((a) => a.status === "Active")?.accountno ||
      accountRows[0]?.accountno ||
      "",
  );

  async function submit(path, payload, method = "post") {
    const result = await flow.run(path, payload, method);
    if (result) close();
    return result;
  }

  const cashModal = modal && ["deposit", "withdraw"].includes(modal.kind);
  return (
    <DashboardLayout
      tabs={tabs}
      activeTab={tab}
      onSelect={(value) => setParams({ tab: value })}
      revision={flow.revision}
      connected={Boolean(totals) && !overview.error}
    >
      <Toast toast={flow.toast} onClose={flow.closeToast} />
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-2 text-xs text-slate-500 dark:text-slate-400">
          <Badge value={totals?.profile.kyc_status} />
          <span>Customer #{user.id}</span>
          <span className="text-slate-300">/</span>
          <span>{accountRows.length} owned accounts</span>
        </div>
        <button
          className={secondaryClass}
          onClick={flow.refresh}
          disabled={flow.busy}
        >
          <Activity className="size-4" />
          Refresh portfolio
        </button>
      </div>
      <ResourceState resource={overview} />

      {tab === "overview" && totals && (
        <>
          <section className="relative overflow-hidden rounded-2xl bg-linear-to-br from-blue-600 to-blue-900 p-7 text-white shadow-lg shadow-blue-600/15">
            <div className="absolute -right-12 -bottom-24 size-80 rounded-full border border-white/10" />
            <p className="text-xs text-blue-200">Total net worth</p>
            <p className="mt-4 text-4xl font-semibold tracking-tight sm:text-5xl">
              {currency(totals.net_worth)}
            </p>
            <p className="mt-4 text-[11px] text-blue-200">
              Account balances + Active FD principal − outstanding loans ·
              fn_customer_net_worth
            </p>
          </section>
          <Metrics
            items={[
              [
                "Liquid balance",
                currency(totals.liquid_balance),
                "Across every account",
              ],
              [
                "Active FD principal",
                currency(totals.fd_principal),
                `Maturity: ${currency(totals.fd_maturity)}`,
              ],
              [
                "Loan liability",
                currency(totals.loan_outstanding),
                "Remaining outstanding balance",
              ],
              [
                "Saved beneficiaries",
                totals.beneficiary_count,
                "Your trusted payee directory",
              ],
            ]}
          />
          <div className="grid gap-6 xl:grid-cols-[1fr_1.2fr]">
            <Panel
              title="Assets & liabilities"
              subtitle="All product balances. Loan liability is shown separately from assets."
            >
              <div
                className="h-72 p-5"
                role="img"
                aria-label="Savings, current, salary, FD assets and loan liability chart"
              >
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart
                    data={[
                      {
                        name: "Savings",
                        value: Number(totals.savings_balance),
                      },
                      {
                        name: "Current",
                        value: Number(totals.current_balance),
                      },
                      { name: "Salary", value: Number(totals.salary_balance) },
                      { name: "FDs", value: Number(totals.fd_principal) },
                      { name: "Loans", value: Number(totals.loan_outstanding) },
                    ]}
                  >
                    <CartesianGrid
                      vertical={false}
                      stroke="var(--chart-grid)"
                      strokeDasharray="3 4"
                    />
                    <XAxis
                      dataKey="name"
                      tick={{ fontSize: 10, fill: "var(--chart-tick)" }}
                      axisLine={false}
                      tickLine={false}
                    />
                    <YAxis
                      tickFormatter={compactCurrency}
                      tick={{ fontSize: 10, fill: "var(--chart-tick)" }}
                      width={65}
                      axisLine={false}
                      tickLine={false}
                    />
                    <Tooltip
                      formatter={(value) => currency(value)}
                      contentStyle={{
                        borderRadius: 12,
                        fontSize: 12,
                        backgroundColor: "var(--chart-surface)",
                        color: "var(--chart-text)",
                        border: "1px solid var(--chart-grid)",
                      }}
                      labelStyle={{ color: "var(--chart-text)" }}
                      cursor={{ fill: "var(--chart-grid)", fillOpacity: 0.3 }}
                    />
                    <Bar
                      dataKey="value"
                      radius={[5, 5, 0, 0]}
                      isAnimationActive={false}
                    >
                      {["Savings", "Current", "Salary", "FDs", "Loans"].map(
                        (name, index) => (
                          <Cell
                            key={name}
                            fill={
                              index === 4
                                ? "#f43f5e"
                                : ["#2563eb", "#38bdf8", "#93c5fd", "#0d9488"][
                                    index
                                  ]
                            }
                          />
                        ),
                      )}
                    </Bar>
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </Panel>
            <Panel
              title="Recent activity"
              subtitle="Every transaction is linked to one of your owned accounts."
            >
              <ResourceState resource={transactions} />
              <DataTable
                searchable={false}
                pageSize={5}
                rows={(transactions.data || []).slice(0, 5)}
                columns={[
                  { key: "accountno", label: "Account" },
                  { key: "type", label: "Type" },
                  moneyColumn("amount", "Amount"),
                  {
                    key: "date",
                    label: "When",
                    render: (row) => dateTime(row.date),
                  },
                ]}
              />
            </Panel>
          </div>
        </>
      )}

      {tab === "accounts" && (
        <>
          <ResourceState resource={accounts} />
          <div className="grid gap-4 md:grid-cols-2 2xl:grid-cols-3">
            {accountRows.map((account) => (
              <section
                key={account.accountno}
                className="rounded-2xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-6 shadow-sm"
              >
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <Landmark className="size-5 text-blue-600 dark:text-blue-400" />
                    <h2 className="text-sm font-semibold">
                      {account.accounttype} account
                    </h2>
                  </div>
                  <Badge value={account.status} />
                </div>
                <p className="mt-5 text-[11px] tracking-widest text-slate-400">
                  ACCOUNT #{account.accountno}
                </p>
                <p className="mt-2 text-3xl font-semibold tracking-tight">
                  {currency(account.balance)}
                </p>
                <dl className="mt-5 grid grid-cols-2 gap-3 text-[11px]">
                  <div>
                    <dt className="text-slate-400">Branch</dt>
                    <dd className="mt-1 text-slate-600 dark:text-slate-300">
                      {account.branchname} · {account.city}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-slate-400">IFSC</dt>
                    <dd className="mt-1 font-medium text-slate-600 dark:text-slate-300">
                      {account.ifsc_code}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-slate-400">Interest rate</dt>
                    <dd className="mt-1">{account.interestrate}% p.a.</dd>
                  </div>
                  <div>
                    <dt className="text-slate-400">Opened</dt>
                    <dd className="mt-1">{account.openingdate}</dd>
                  </div>
                </dl>
                <div className="mt-5 flex gap-2 border-t border-slate-100 dark:border-slate-700 pt-4">
                  <button
                    className={secondaryClass}
                    onClick={() => setModal({ kind: "deposit", account })}
                  >
                    <ArrowDownToLine className="size-3.5" />
                    Deposit
                  </button>
                  <button
                    className={secondaryClass}
                    onClick={() => setModal({ kind: "withdraw", account })}
                  >
                    <ArrowUpFromLine className="size-3.5" />
                    Withdraw
                  </button>
                </div>
              </section>
            ))}
          </div>
          {!accounts.loading && !accountRows.length && (
            <Panel>
              <p className="p-8 text-sm text-slate-400">
                No accounts yet. A bank official can open your first account.
              </p>
            </Panel>
          )}
          <Panel
            title="Passbook statement"
            subtitle="Filter by account, transaction type, or payment channel."
          >
            <div className="grid gap-3 p-5 sm:grid-cols-3">
              {[
                [
                  "account_no",
                  "All accounts",
                  accountRows.map((a) =>
                    option(a.accountno, `#${a.accountno} · ${a.accounttype}`),
                  ),
                ],
                [
                  "txn_type",
                  "All transaction types",
                  choices(["Deposit", "Withdrawal", "Transfer"]),
                ],
                ["payment_mode", "All payment modes", modes],
              ].map(([name, label, options]) => (
                <select
                  key={name}
                  aria-label={label}
                  className={inputClass}
                  value={filters[name]}
                  onChange={(e) =>
                    setFilters((current) => ({
                      ...current,
                      [name]: e.target.value,
                    }))
                  }
                >
                  <option value="">{label}</option>
                  {options.map((o) => (
                    <option key={o.value} value={o.value}>
                      {o.label}
                    </option>
                  ))}
                </select>
              ))}
            </div>
            <ResourceState resource={transactions} />
            <DataTable
              rows={transactions.data || []}
              columns={transactionColumns}
            />
          </Panel>
        </>
      )}

      {tab === "transfers" && (
        <div className="grid items-start gap-6 xl:grid-cols-[.9fr_1.1fr]">
          <Panel
            title="Transfer money"
            subtitle="Atomic payments with account status and balance checks."
          >
            <div className="p-6">
              <div className="mb-5 grid grid-cols-2 gap-2 rounded-xl bg-slate-100 dark:bg-slate-800 p-1.5">
                {[
                  ["internal", "Internal account"],
                  ["beneficiary", "Saved beneficiary"],
                ].map(([value, label]) => (
                  <button
                    key={value}
                    onClick={() => setDestination(value)}
                    className={`rounded-lg px-2 py-2.5 text-[11px] font-semibold ${destination === value ? "bg-white dark:bg-slate-900 text-blue-600 dark:text-blue-400 shadow-sm" : "text-slate-500 dark:text-slate-400"}`}
                  >
                    {label}
                  </button>
                ))}
              </div>
              <WorkflowForm
                key={destination + defaultAccount}
                busy={flow.busy}
                submitLabel="Commit transfer"
                initial={{ sender: defaultAccount, mode: "UPI" }}
                fields={[
                  select("sender", "Your sender account", funding, {
                    wide: true,
                  }),
                  destination === "internal"
                    ? number("receiver", "Receiver account number", {
                        min: 1,
                        max: 2147483647,
                        step: 1,
                        wide: true,
                      })
                    : select(
                        "beneficiary_id",
                        "Saved beneficiary",
                        beneficiaryRows.map((b) =>
                          option(
                            b.beneficiaryid,
                            `${b.beneficiaryname} · ${b.bankname} · ${b.linkedaccountno}`,
                          ),
                        ),
                        { wide: true },
                      ),
                  number("amount", "Amount (INR)"),
                  select("mode", "Payment mode", modes),
                  text("remarks", "Payment remarks", {
                    required: false,
                    maxLength: 180,
                    wide: true,
                  }),
                ]}
                onSubmit={(values) =>
                  flow.run("/api/transaction/transfer", {
                    ...values,
                    customer_id: Number(user.id),
                    ...(destination === "internal"
                      ? { receiver: Number(values.receiver) }
                      : { beneficiary_id: Number(values.beneficiary_id) }),
                  })
                }
              />
              <p className="mt-5 rounded-xl bg-slate-50 dark:bg-slate-950 p-3 text-[10px] leading-5 text-slate-400">
                Internal transfers execute the database’s locked transfer logic.
                External beneficiary payments are recorded as outward transfers
                in this local banking system.
              </p>
            </div>
          </Panel>
          <Panel
            title="Saved beneficiaries"
            subtitle="IFSCs resolve through Bank_Directory. Limits apply cumulatively per day."
            action={
              <button
                className={buttonClass}
                onClick={() => setModal({ kind: "beneficiary" })}
              >
                <CirclePlus className="size-4" />
                Add payee
              </button>
            }
          >
            <ResourceState resource={beneficiaries} />
            <DataTable
              rows={beneficiaryRows}
              columns={[
                {
                  key: "beneficiaryname",
                  label: "Payee",
                  render: (b) => (
                    <div>
                      <p className="font-semibold">{b.beneficiaryname}</p>
                      <p className="mt-1 text-[10px] text-slate-400">
                        #{b.beneficiaryid} · Account {b.linkedaccountno}
                      </p>
                    </div>
                  ),
                },
                {
                  key: "bankname",
                  label: "Bank / IFSC",
                  render: (b) => (
                    <div>
                      {b.bankname}
                      <p className="text-[10px] text-slate-400">
                        {b.ifsc_code}
                      </p>
                    </div>
                  ),
                },
                moneyColumn("maxtransferlimit", "Daily limit"),
                {
                  key: "delete",
                  label: "",
                  render: (b) => (
                    <button
                      aria-label={`Delete beneficiary ${b.beneficiaryname}`}
                      disabled={flow.busy}
                      className="rounded-lg p-2 text-rose-500 dark:text-rose-400 hover:bg-rose-50 dark:hover:bg-rose-950/40"
                      onClick={() =>
                        setModal({ kind: "delete-beneficiary", beneficiary: b })
                      }
                    >
                      <Trash2 className="size-4" />
                    </button>
                  ),
                },
              ]}
            />
          </Panel>
        </div>
      )}

      {tab === "loans" && (
        <>
          <ResourceState resource={loans} />
          <div className="grid gap-5 xl:grid-cols-2">
            {loanRows.map((loan) => {
              const paid = Math.max(
                0,
                Math.min(
                  100,
                  (1 -
                    Number(loan.outstandingbalance) /
                      Number(loan.principalamount)) *
                    100,
                ),
              );
              return (
                <Panel
                  key={loan.loanid}
                  title={`${loan.loantype} Loan #${loan.loanid}`}
                  subtitle={`${loan.branchname} · Issued ${loan.issuedate}`}
                  action={<Badge value={loan.status} />}
                >
                  <div className="p-6">
                    <div className="grid grid-cols-2 gap-5">
                      <div>
                        <p className="text-[11px] text-slate-400">
                          Outstanding liability
                        </p>
                        <p className="mt-1 text-2xl font-semibold">
                          {currency(loan.outstandingbalance)}
                        </p>
                      </div>
                      <div>
                        <p className="text-[11px] text-slate-400">
                          Monthly EMI · generated
                        </p>
                        <p className="mt-1 text-xl font-semibold text-blue-600 dark:text-blue-400">
                          {currency(loan.emi_amount)}
                        </p>
                      </div>
                    </div>
                    <p className="mt-5 text-[11px] text-slate-500 dark:text-slate-400">
                      Principal {currency(loan.principalamount)} ·{" "}
                      {loan.interestrate}% p.a. · {loan.tenuremonths} months
                    </p>
                    <div className="mt-3 h-1.5 overflow-hidden rounded-full bg-slate-100 dark:bg-slate-800">
                      <div
                        className="h-full rounded-full bg-blue-500"
                        style={{ width: `${paid}%` }}
                      />
                    </div>
                    <p className="mt-2 text-[10px] text-slate-400">
                      {paid.toFixed(1)}% of original principal cleared
                    </p>
                    <div className="mt-5 flex flex-wrap gap-2">
                      <button
                        className={buttonClass}
                        disabled={
                          ["Closed", "Pending"].includes(loan.status) ||
                          flow.busy
                        }
                        onClick={() => setModal({ kind: "emi", loan })}
                      >
                        Pay monthly EMI
                      </button>
                      <button
                        className={secondaryClass}
                        onClick={() => setSelectedLoan(String(loan.loanid))}
                      >
                        View repayments
                      </button>
                    </div>
                  </div>
                </Panel>
              );
            })}
          </div>
          {!loans.loading && !loanRows.length && (
            <Panel>
              <p className="p-8 text-sm text-slate-400">
                No loans on your profile.
              </p>
            </Panel>
          )}
          <Panel
            title="EMI repayment history"
            subtitle="Successful inserts fire trg_loan_repayment. The schema records payments, not a future due-date schedule."
          >
            <div className="p-5">
              <select
                aria-label="Loan repayment history"
                className={`${inputClass} max-w-md`}
                value={selectedLoan}
                onChange={(e) => setSelectedLoan(e.target.value)}
              >
                <option value="">Select a loan to inspect payments…</option>
                {loanRows.map((l) => (
                  <option key={l.loanid} value={l.loanid}>
                    #{l.loanid} · {l.loantype} · {l.status}
                  </option>
                ))}
              </select>
            </div>
            <ResourceState resource={repayments} />
            <DataTable
              rows={repayments.data || []}
              columns={[
                { key: "paymentid", label: "Payment" },
                moneyColumn("amountpaid", "Amount paid"),
                { key: "paymentmode", label: "Mode" },
                {
                  key: "paymentstatus",
                  label: "Result",
                  render: (r) => <Badge value={r.paymentstatus} />,
                },
                {
                  key: "paymentdate",
                  label: "Date",
                  render: (r) => dateTime(r.paymentdate),
                },
              ]}
              empty={
                selectedLoan
                  ? "No repayments recorded for this loan."
                  : "Choose a loan above."
              }
            />
          </Panel>
        </>
      )}

      {tab === "fds" && (
        <>
          <ResourceState resource={fds} />
          <Metrics
            items={[
              [
                "Active FD principal",
                currency(totals?.fd_principal || 0),
                "Currently invested",
              ],
              [
                "Generated maturity",
                currency(totals?.fd_maturity || 0),
                "Active deposit obligations",
              ],
              ["Your deposits", fdRows.length, "Active, matured, and closed"],
              [
                "Interest method",
                "Actual / 365",
                "Simple interest, computed in PostgreSQL",
              ],
            ]}
          />
          <Panel
            title="Your fixed deposit vault"
            subtitle="Generated maturity values are read directly from Fixed_Deposit."
            action={
              <button
                className={buttonClass}
                onClick={() => setModal({ kind: "fd" })}
              >
                <CirclePlus className="size-4" />
                Open fixed deposit
              </button>
            }
          >
            <DataTable
              rows={fdRows}
              columns={fdColumns.filter((c) => c.key !== "customername")}
            />
          </Panel>
        </>
      )}

      {tab === "profile" && totals && (
        <Panel
          title={`${totals.profile.firstname} ${totals.profile.lastname}`}
          subtitle={`Customer #${user.id} · Personal KYC record`}
          action={<Badge value={totals.profile.kyc_status} />}
        >
          <dl className="grid gap-x-8 gap-y-6 p-6 sm:grid-cols-2 xl:grid-cols-3">
            {[
              ["Customer ID", totals.profile.customerid],
              [
                "Full name",
                `${totals.profile.firstname} ${totals.profile.lastname}`,
              ],
              ["PAN number", totals.profile.pan_number],
              ["Gender", totals.profile.gender],
              ["Age", totals.profile.age],
              ["Phone", totals.profile.phone],
              ["Email", totals.profile.email],
              ["Address", totals.profile.address],
              ["KYC verification", totals.profile.kyc_status],
            ].map(([label, value]) => (
              <div key={label}>
                <dt className="text-[10px] font-semibold tracking-wide text-slate-400 uppercase">
                  {label}
                </dt>
                <dd className="mt-2 text-sm leading-6 break-words text-slate-700 dark:text-slate-300">
                  {value}
                </dd>
              </div>
            ))}
          </dl>
        </Panel>
      )}

      {cashModal && (
        <Modal
          title={
            modal.kind === "deposit" ? "Cash / self deposit" : "Withdraw funds"
          }
          subtitle="Balance update, history insert, and audit trigger commit together."
          onClose={close}
        >
          <WorkflowForm
            busy={flow.busy}
            submitLabel={
              modal.kind === "deposit" ? "Commit deposit" : "Commit withdrawal"
            }
            initial={{
              account_no: String(modal.account.accountno),
              mode: "Cash",
            }}
            fields={[
              select("account_no", "Your account", funding, { wide: true }),
              number("amount", "Amount (INR)"),
              select("mode", "Payment mode", modes),
              text("remarks", "Remarks", {
                required: false,
                wide: true,
                maxLength: 200,
              }),
            ]}
            onSubmit={(values) =>
              submit(`/api/transaction/${modal.kind}`, {
                ...values,
                customer_id: Number(user.id),
              })
            }
          />
        </Modal>
      )}
      {modal?.kind === "beneficiary" && (
        <Modal
          title="Add a trusted beneficiary"
          subtitle="Use an existing IFSC or register a bank directory entry atomically."
          onClose={close}
        >
          <WorkflowForm
            busy={flow.busy}
            fields={beneficiaryFields(lookups.data?.bank_directory || [])}
            submitLabel="Save beneficiary"
            onSubmit={(values) =>
              submit(`${base}/beneficiaries`, beneficiaryPayload(values))
            }
          />
        </Modal>
      )}
      {modal?.kind === "delete-beneficiary" && (
        <Modal title="Remove saved beneficiary" onClose={close}>
          <p className="mb-5 text-sm text-slate-500 dark:text-slate-400">
            Remove {modal.beneficiary.beneficiaryname} (account{" "}
            {modal.beneficiary.linkedaccountno}) from your saved payees?
          </p>
          <button
            className={buttonClass}
            disabled={flow.busy}
            onClick={() =>
              submit(
                `/api/beneficiaries/${modal.beneficiary.beneficiaryid}?customer_id=${user.id}`,
                undefined,
                "delete",
              )
            }
          >
            Remove beneficiary
          </button>
        </Modal>
      )}
      {modal?.kind === "emi" && (
        <Modal
          title={`Pay EMI · Loan #${modal.loan.loanid}`}
          subtitle={`Required installment ${currency(Math.min(Number(modal.loan.emi_amount), Number(modal.loan.outstandingbalance)))}. Final payment is capped at outstanding balance.`}
          onClose={close}
        >
          <WorkflowForm
            busy={flow.busy}
            submitLabel="Pay monthly EMI"
            initial={{ account_no: defaultAccount }}
            fields={[
              select("account_no", "Debit your account", funding, {
                wide: true,
              }),
            ]}
            onSubmit={async (values) => {
              const result = await submit("/api/loans/pay-emi", {
                ...values,
                customer_id: Number(user.id),
                loan_id: modal.loan.loanid,
              });
              if (result) setSelectedLoan(String(modal.loan.loanid));
            }}
          />
          <p className="mt-4 text-[10px] leading-5 text-slate-400">
            Lab repayment convention: the full EMI reduces OutstandingBalance.
            The existing schema has no principal/interest allocation schedule.
          </p>
        </Modal>
      )}
      {modal?.kind === "fd" && (
        <Modal
          title="Open a new fixed deposit"
          subtitle="Funding debit and FD creation are one atomic transaction."
          onClose={close}
        >
          <WorkflowForm
            busy={flow.busy}
            submitLabel="Fund & open fixed deposit"
            initial={{
              account_no: defaultAccount,
              amount: "10000",
              interest_rate: "7.00",
              start_date: today,
              end_date: plusDays(today, 365),
            }}
            fields={[
              select("account_no", "Funding account", funding, { wide: true }),
              number("amount", "Deposit principal (INR)", { min: 1000 }),
              number("interest_rate", "Interest rate %", { min: 0, max: 999 }),
              text("start_date", "Start date", { type: "date" }),
              text("end_date", "Maturity date", { type: "date" }),
            ]}
            preview={(values) => <FDPreview values={values} />}
            onSubmit={(values) => submit(`${base}/fixed-deposits`, values)}
          />
        </Modal>
      )}
    </DashboardLayout>
  );
}
