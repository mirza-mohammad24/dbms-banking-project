import { useState } from "react";
import { Navigate, useNavigate } from "react-router-dom";
import {
  ArrowRight,
  Building2,
  Landmark,
  LoaderCircle,
  UserRound,
} from "lucide-react";
import { api, apiError } from "../lib/api";
import { saveSession, useSession } from "../lib/session";
import { useResource } from "../lib/hooks";
import ThemeToggle from "../components/ThemeToggle";
import {
  CustomerPicker,
  inputClass,
  ResourceState,
} from "../components/BankingUI";

export default function Login() {
  const navigate = useNavigate();
  const existing = useSession();
  const [role, setRole] = useState("Customer");
  const [customerId, setCustomerId] = useState("1");
  const [employee, setEmployee] = useState("admin");
  const [directId, setDirectId] = useState("");
  const [identity, setIdentity] = useState("customer");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const customers = useResource("/api/directory/customers-preview");
  const officials = useResource("/api/directory/employees-preview");
  if (existing)
    return (
      <Navigate
        to={
          existing.role === "Admin" ? "/admin/dashboard" : "/customer/dashboard"
        }
        replace
      />
    );
  async function signIn(event) {
    event.preventDefault();
    setBusy(true);
    setError("");
    try {
      const payload =
        role === "Admin"
          ? {
              role,
              id: employee === "admin" ? 1 : Number(employee),
              employee_id: employee === "admin" ? null : Number(employee),
            }
          : {
              role,
              id: Number(directId || customerId),
              identity_type: directId ? identity : "customer",
            };
      const { data } = await api.post("/api/login", payload);
      saveSession(data.user);
      navigate(role === "Admin" ? "/admin/dashboard" : "/customer/dashboard", {
        replace: true,
      });
    } catch (err) {
      setError(apiError(err));
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="min-h-screen bg-slate-50 dark:bg-slate-950 font-sans text-slate-900 dark:text-slate-100 lg:grid lg:grid-cols-[.9fr_1.1fr]">
      <section className="relative hidden flex-col overflow-hidden bg-slate-950 p-14 text-white lg:flex">
        <div className="absolute -top-24 -right-32 size-[600px] rounded-full border border-white/5" />
        <div className="absolute right-[-80px] bottom-0 size-96 rounded-full bg-blue-600/20 blur-[100px]" />
        <div className="relative flex items-center gap-3">
          <span className="rounded-xl bg-blue-600 p-3">
            <Landmark className="size-6" />
          </span>
          <span className="text-2xl font-bold tracking-tight">
            CoreBank<span className="text-blue-400">.</span>
          </span>
        </div>
        <div className="relative my-auto py-16">
          <span className="rounded-full border border-blue-400/20 bg-blue-500/10 px-3 py-1.5 text-[10px] font-medium text-blue-300">
            Connected banking, from the inside out.
          </span>
          <h1 className="mt-8 text-5xl leading-tight font-semibold tracking-tight">
            Every relationship.
            <br />
            <span className="text-blue-400">Every possibility.</span>
          </h1>
          <p className="mt-6 max-w-sm text-sm leading-8 text-slate-400">
            Explore the complete customer journey. From opening an account to
            building a portfolio, every action connects to a real banking
            record.
          </p>
          <div className="mt-10 grid grid-cols-2 gap-5 border-t border-white/10 pt-6">
            <div>
              <p className="text-2xl font-semibold">
                {customers.data?.length ?? "—"}
              </p>
              <p className="mt-1 text-[11px] text-slate-500 dark:text-slate-400">
                Real customer profiles
              </p>
            </div>
            <div>
              <p className="text-2xl font-semibold">12</p>
              <p className="mt-1 text-[11px] text-slate-500 dark:text-slate-400">
                Connected banking tables
              </p>
            </div>
          </div>
        </div>
        <p className="relative text-[10px] text-slate-500 dark:text-slate-400">
          BCSE302P · Core Banking & Transaction Management System
        </p>
      </section>
      <main className="flex items-center justify-center p-5 py-10 sm:p-10">
        <div className="w-full max-w-xl rounded-3xl border border-slate-200/80 dark:border-slate-700/80 bg-white dark:bg-slate-900 p-6 shadow-xl shadow-slate-200/40 dark:shadow-black/20 sm:p-10">
          <div className="mb-5 flex justify-end">
            <ThemeToggle />
          </div>
          <div className="mb-6 inline-flex rounded-2xl bg-blue-50 dark:bg-blue-950/40 p-3 text-blue-600 dark:text-blue-400">
            <Landmark className="size-6" />
          </div>
          <h2 className="text-3xl font-semibold tracking-tight">
            Your banking workspace
          </h2>
          <p className="mt-2 text-sm text-slate-400">
            Choose who you’re presenting as. See exactly what they own.
          </p>
          <div className="my-7 grid grid-cols-2 gap-2 rounded-xl bg-slate-100 dark:bg-slate-800 p-1.5">
            {[
              ["Customer", UserRound, "Customer NetBanking"],
              ["Admin", Building2, "Bank Official Portal"],
            ].map(([value, Icon, label]) => (
              <button
                key={value}
                onClick={() => {
                  setRole(value);
                  setError("");
                }}
                className={`flex items-center justify-center gap-2 rounded-lg px-2 py-3 text-[11px] font-semibold transition ${role === value ? "bg-white dark:bg-slate-900 text-blue-700 dark:text-blue-300 shadow-sm" : "text-slate-500 dark:text-slate-400 hover:text-slate-800 dark:hover:text-slate-200"}`}
              >
                <Icon className="size-4" />
                {label}
              </button>
            ))}
          </div>
          <form onSubmit={signIn} className="space-y-5">
            {role === "Customer" ? (
              <>
                <ResourceState resource={customers} />
                <CustomerPicker
                  customers={customers.data || []}
                  value={customerId}
                  onChange={(value) => {
                    setCustomerId(value);
                    setDirectId("");
                  }}
                />
                <details className="rounded-xl border border-slate-200 dark:border-slate-700 p-4">
                  <summary className="cursor-pointer text-xs font-medium text-slate-500 dark:text-slate-400">
                    Use a Customer ID or Account No directly
                  </summary>
                  <div className="mt-3 grid grid-cols-2 gap-3">
                    <select
                      aria-label="Direct login identifier type"
                      className={inputClass}
                      value={identity}
                      onChange={(e) => setIdentity(e.target.value)}
                    >
                      <option value="customer">Customer ID</option>
                      <option value="account">Account No</option>
                    </select>
                    <input
                      aria-label="Direct ID or account number"
                      className={inputClass}
                      type="number"
                      min="1"
                      max="2147483647"
                      step="1"
                      placeholder="Enter ID"
                      value={directId}
                      onChange={(e) => setDirectId(e.target.value)}
                    />
                  </div>
                </details>
              </>
            ) : (
              <>
                <ResourceState resource={officials} />
                <label className="mb-2 block text-xs font-semibold">
                  Bank official profile
                </label>
                <select
                  aria-label="Bank official profile"
                  className={inputClass}
                  value={employee}
                  onChange={(e) => setEmployee(e.target.value)}
                >
                  <option value="admin">
                    System Administrator · All branches
                  </option>
                  {(officials.data || []).map((e) => (
                    <option key={e.employeeid} value={e.employeeid}>
                      #{e.employeeid} · {e.firstname} {e.lastname} | {e.role} |{" "}
                      {e.branchname}
                    </option>
                  ))}
                </select>
                <div className="rounded-xl border border-blue-100 dark:border-blue-800 bg-blue-50 dark:bg-blue-950/40 p-4 text-xs leading-6 text-blue-600 dark:text-blue-400">
                  Explore customer ownership, approve KYC, originate loans,
                  manage accounts, and inspect every database event.
                </div>
              </>
            )}
            {error && (
              <p
                role="alert"
                className="rounded-xl border border-rose-100 dark:border-rose-800 bg-rose-50 dark:bg-rose-950/40 p-3 text-xs whitespace-pre-line text-rose-700 dark:text-rose-300"
              >
                {error}
              </p>
            )}
            <button
              disabled={
                busy || (role === "Customer" && !customerId && !directId)
              }
              className="flex w-full items-center justify-center gap-2 rounded-xl bg-blue-600 py-3.5 text-sm font-semibold text-white shadow-lg shadow-blue-600/20 hover:bg-blue-700 disabled:opacity-50"
            >
              {busy ? (
                <LoaderCircle className="size-4 animate-spin" />
              ) : (
                <ArrowRight className="size-4" />
              )}
              {busy ? "Opening workspace…" : "Enter workspace"}
            </button>
            <p className="text-center text-[10px] leading-5 text-slate-400">
              Local demonstration · identities are simulated
              <br />
              Customer and account relationships come directly from PostgreSQL.
            </p>
          </form>
        </div>
      </main>
    </div>
  );
}
