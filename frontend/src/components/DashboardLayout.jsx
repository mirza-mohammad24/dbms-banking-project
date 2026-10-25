import { useState } from "react";
import { useNavigate } from "react-router-dom";
import {
  ArrowLeftRight,
  Building2,
  ChevronDown,
  Landmark,
  LogOut,
  Menu,
  ShieldCheck,
  X,
} from "lucide-react";
import { api, apiError } from "../lib/api";
import { clearSession, saveSession, useSession } from "../lib/session";
import { useResource } from "../lib/hooks";
import { CustomerPicker, inputClass } from "./BankingUI";
import ThemeToggle from "./ThemeToggle";

function IdentitySwitcher({ revision }) {
  const user = useSession();
  const navigate = useNavigate();
  const [open, setOpen] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const customers = useResource("/api/directory/customers-preview", revision);
  const employees = useResource("/api/directory/employees-preview", revision);
  async function select(payload) {
    setPending(true);
    setError("");
    try {
      const { data } = await api.post("/api/login", payload);
      saveSession(data.user);
      setOpen(false);
      navigate(
        payload.role === "Admin" ? "/admin/dashboard" : "/customer/dashboard",
      );
    } catch (err) {
      setError(apiError(err));
    } finally {
      setPending(false);
    }
  }
  return (
    <div className="relative">
      <button
        aria-expanded={open}
        onClick={() => setOpen(!open)}
        className="flex items-center gap-2 rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 px-3 py-2 text-xs font-medium text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-950"
      >
        <ArrowLeftRight className="size-4 text-blue-600 dark:text-blue-400" />
        <span className="hidden sm:inline">Switch identity</span>
        <ChevronDown className="size-3" />
      </button>
      {open && (
        <div className="absolute top-full right-0 z-30 mt-3 max-h-[80vh] w-[min(90vw,460px)] overflow-auto rounded-2xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-5 shadow-2xl shadow-slate-900/15">
          <div className="mb-4 flex items-center justify-between">
            <div>
              <p className="text-sm font-semibold">
                Presenter’s identity switcher
              </p>
              <p className="mt-1 text-[10px] text-slate-400">
                Real customer ownership · instant workspace change
              </p>
            </div>
            <button aria-label="Close switcher" onClick={() => setOpen(false)}>
              <X className="size-4 text-slate-400" />
            </button>
          </div>
          <button
            disabled={pending}
            className="mb-5 flex w-full items-center gap-3 rounded-xl bg-slate-950 p-3 text-left text-xs text-white disabled:opacity-50"
            onClick={() =>
              select(
                user.role === "Admin"
                  ? {
                      role: "Customer",
                      id: Number(localStorage.getItem("last_customer_id") || 1),
                    }
                  : { role: "Admin", id: 1 },
              )
            }
          >
            <Building2 className="size-4 text-blue-300" />
            {user.role === "Admin"
              ? "Jump to Customer NetBanking"
              : "Jump to Bank Official Portal"}
          </button>
          <fieldset disabled={pending}>
            <CustomerPicker
              compact
              label="Switch to a customer"
              customers={customers.data || []}
              value={user.role === "Customer" ? user.id : ""}
              onChange={(id) => {
                if (id) select({ role: "Customer", id: Number(id) });
              }}
            />
            <label className="mt-5 mb-2 block text-[11px] font-semibold text-slate-600 dark:text-slate-300">
              Switch to a bank official
            </label>
            <select
              aria-label="Switch bank official"
              className={inputClass}
              value={user.employee_id || "admin"}
              onChange={(e) =>
                select(
                  e.target.value === "admin"
                    ? { role: "Admin", id: 1 }
                    : {
                        role: "Admin",
                        id: Number(e.target.value),
                        employee_id: Number(e.target.value),
                      },
                )
              }
            >
              <option value="admin">System Administrator</option>
              {(employees.data || []).map((e) => (
                <option key={e.employeeid} value={e.employeeid}>
                  #{e.employeeid} · {e.firstname} {e.lastname} · {e.role} ·{" "}
                  {e.branchname}
                </option>
              ))}
            </select>
          </fieldset>
          {(error || customers.error || employees.error) && (
            <p
              role="alert"
              className="mt-3 text-xs text-rose-600 dark:text-rose-400"
            >
              {error || customers.error || employees.error}
            </p>
          )}
        </div>
      )}
    </div>
  );
}

export default function DashboardLayout({
  children,
  tabs,
  activeTab,
  onSelect,
  revision = 0,
  connected = true,
}) {
  const user = useSession();
  const navigate = useNavigate();
  const [mobile, setMobile] = useState(false);
  const admin = user.role === "Admin";
  const active = tabs.find((tab) => tab.id === activeTab) || tabs[0];
  return (
    <div className="min-h-screen bg-slate-50 dark:bg-slate-950 font-sans text-slate-900 dark:text-slate-100 antialiased">
      {mobile && (
        <button
          aria-label="Close navigation overlay"
          onClick={() => setMobile(false)}
          className="fixed inset-0 z-30 bg-slate-950/40 lg:hidden"
        />
      )}
      <aside
        className={`fixed inset-y-0 left-0 z-40 flex w-64 flex-col bg-slate-950 px-5 py-7 text-slate-400 transition-transform lg:visible lg:translate-x-0 ${mobile ? "visible translate-x-0" : "invisible -translate-x-full"}`}
      >
        <div className="mb-10 flex items-center gap-3 px-2">
          <span className="grid size-10 place-items-center rounded-xl bg-blue-600 text-white shadow-lg shadow-blue-600/25">
            <Landmark className="size-6" />
          </span>
          <span className="text-xl font-bold tracking-tight text-white">
            CoreBank<span className="text-blue-400">.</span>
          </span>
          <button
            className="ml-auto lg:hidden"
            aria-label="Close navigation"
            onClick={() => setMobile(false)}
          >
            <X className="size-4" />
          </button>
        </div>
        <p className="mb-3 px-3 text-[9px] font-bold tracking-[.18em] text-slate-500 dark:text-slate-400 uppercase">
          {admin ? "Bank official workspace" : "Customer NetBanking"}
        </p>
        <nav className="min-h-0 flex-1 space-y-1 overflow-y-auto">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              aria-current={activeTab === tab.id ? "page" : undefined}
              onClick={() => {
                onSelect(tab.id);
                setMobile(false);
              }}
              className={`flex w-full items-center gap-3 rounded-xl px-3 py-3 text-left text-[11px] font-medium transition ${activeTab === tab.id ? "bg-blue-500/15 text-blue-300 ring-1 ring-inset ring-blue-400/15" : "hover:bg-white/5 hover:text-slate-200"}`}
            >
              <tab.icon className="size-[18px] shrink-0" />
              <span>{tab.label}</span>
              {activeTab === tab.id && (
                <span className="ml-auto size-1.5 shrink-0 rounded-full bg-blue-400" />
              )}
            </button>
          ))}
        </nav>
        <div className="mt-5 rounded-xl border border-slate-800 bg-slate-900/60 p-3">
          <div className="flex items-center gap-2 text-[10px] text-slate-300">
            <ShieldCheck className="size-4 text-blue-400" />
            PostgreSQL-backed workflows
          </div>
          <p className="mt-2 text-[10px] leading-5 text-slate-500 dark:text-slate-400">
            12 normalized tables · live views
            <br />
            Triggers, functions & cursor batches
          </p>
        </div>
        <div className="mt-4 flex items-center gap-2 px-2 text-[10px]">
          <span
            className={`size-1.5 rounded-full ${connected ? "bg-emerald-400" : "bg-amber-400"}`}
          />
          {connected
            ? "Banking API connected"
            : "Connecting / refresh required"}
        </div>
        <div className="mt-5 flex items-center justify-between border-t border-slate-800 px-1 pt-5">
          <div className="min-w-0">
            <p className="truncate text-xs font-semibold text-slate-200">
              {user.name}
            </p>
            <p className="mt-1 text-[10px] text-slate-500 dark:text-slate-400">
              {user.title || "Customer"} · #{user.id}
            </p>
          </div>
          <button
            aria-label="Sign out"
            onClick={() => {
              clearSession();
              navigate("/", { replace: true });
            }}
            className="rounded-lg p-2 hover:bg-slate-800 hover:text-white"
          >
            <LogOut className="size-4" />
          </button>
        </div>
      </aside>
      <main className="min-w-0 lg:ml-64">
        <header className="sticky top-0 z-20 flex h-18 items-center justify-between gap-3 border-b border-slate-200/80 dark:border-slate-700/80 bg-white/95 dark:bg-slate-900/95 px-5 backdrop-blur-sm sm:px-8">
          <div className="flex min-w-0 items-center gap-3">
            <button
              aria-label="Open navigation"
              className="rounded-lg p-2 text-slate-500 dark:text-slate-400 lg:hidden"
              onClick={() => setMobile(true)}
            >
              <Menu className="size-5" />
            </button>
            <div className="min-w-0">
              <p className="truncate text-xs font-semibold">{active.label}</p>
              <p className="mt-1 truncate text-[10px] text-slate-400">
                {admin
                  ? user.branchname || "All branches · System administration"
                  : `${user.name} · Customer #${user.id}`}
              </p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <ThemeToggle />
            <IdentitySwitcher revision={revision} />
          </div>
        </header>
        <div className="mx-auto max-w-[1700px] space-y-6 p-5 sm:p-8">
          <div>
            <p className="mb-2 text-[9px] font-bold tracking-[.18em] text-blue-600 dark:text-blue-400 uppercase">
              {admin
                ? "Bank operations & administration"
                : "Your money, clearly connected"}
            </p>
            <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">
              {active.label}
              <span className="text-blue-500 dark:text-blue-400">.</span>
            </h1>
            <p className="mt-2 text-xs leading-6 text-slate-400">
              {active.description}
            </p>
          </div>
          {children}
          <footer className="flex flex-wrap justify-between gap-2 border-t border-slate-200 dark:border-slate-700 pt-5 text-[10px] text-slate-400">
            <span>CoreBank · Core Banking & Transaction Management</span>
            <span>Local lab · simulated identity · INR</span>
          </footer>
        </div>
      </main>
    </div>
  );
}
