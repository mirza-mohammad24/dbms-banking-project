import { useEffect, useRef, useState, useId } from "react";
import { createPortal } from "react-dom";
import {
  Search,
  X,
  ChevronLeft,
  ChevronRight,
  LoaderCircle,
  ArrowUpRight,
  Landmark,
} from "lucide-react";
import { currency, dateTime } from "../lib/api";
import { useDebounced, useResource } from "../lib/hooks";

export const inputClass =
  "w-full rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 px-3.5 py-2.5 text-sm text-slate-800 dark:text-slate-200 outline-none transition focus:border-blue-500 focus:ring-4 focus:ring-blue-500/10 disabled:bg-slate-50 dark:disabled:bg-slate-950 disabled:text-slate-400";
export const buttonClass =
  "inline-flex items-center justify-center gap-2 rounded-xl bg-blue-600 px-4 py-2.5 text-xs font-semibold text-white shadow-sm transition hover:bg-blue-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-500 disabled:cursor-wait disabled:opacity-50";
export const secondaryClass =
  "inline-flex items-center justify-center gap-2 rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 px-3.5 py-2.5 text-xs font-medium text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-950 disabled:opacity-40";
export const option = (value, label) => ({ value, label });
export const choices = (values) => values.map((value) => option(value, value));
export const moneyColumn = (key, label) => ({
  key,
  label,
  render: (row) => (
    <span className="font-semibold whitespace-nowrap tabular-nums">
      {currency(row[key])}
    </span>
  ),
});
export const statusColumn = {
  key: "status",
  label: "Status",
  render: (row) => <Badge value={row.status} />,
};
export const ownerColumn = {
  key: "customername",
  label: "Customer",
  render: (row) => (
    <div>
      <p className="font-medium text-slate-800 dark:text-slate-200">
        {row.customername}
      </p>
      <p className="mt-1 text-[10px] text-slate-400">
        Customer #{row.customerid}
      </p>
    </div>
  ),
};

export function Badge({ value }) {
  const style = ["Active", "Approved", "Success", "Matured"].includes(value)
    ? "bg-emerald-50 dark:bg-emerald-950/40 text-emerald-700 dark:text-emerald-300 ring-emerald-600/10"
    : ["Frozen", "Defaulted", "Rejected", "Failed"].includes(value)
      ? "bg-rose-50 dark:bg-rose-950/40 text-rose-700 dark:text-rose-300 ring-rose-600/10"
      : ["Pending", "Dormant"].includes(value)
        ? "bg-amber-50 dark:bg-amber-950/40 text-amber-700 dark:text-amber-300 ring-amber-600/10"
        : "bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-300 ring-slate-500/10";
  return (
    <span
      className={`inline-flex rounded-md px-2 py-1 text-[10px] font-semibold whitespace-nowrap ring-1 ring-inset ${style}`}
    >
      {value || "Not set"}
    </span>
  );
}

export function Panel({ title, subtitle, action, children, className = "" }) {
  return (
    <section
      className={`min-w-0 overflow-hidden rounded-2xl border border-slate-200/80 dark:border-slate-700/80 bg-white dark:bg-slate-900 shadow-sm ${className}`}
    >
      {(title || action) && (
        <div className="flex flex-wrap items-center justify-between gap-3 border-b border-slate-100 dark:border-slate-700 px-5 py-5 sm:px-6">
          <div>
            <h2 className="text-sm font-semibold text-slate-900 dark:text-slate-100">
              {title}
            </h2>
            {subtitle && (
              <p className="mt-1 text-xs leading-5 text-slate-400">
                {subtitle}
              </p>
            )}
          </div>
          {action}
        </div>
      )}
      {children}
    </section>
  );
}

export function Metrics({ items }) {
  return (
    <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
      {items.map(([label, value, caption]) => (
        <div
          key={label}
          className="rounded-2xl border border-slate-200/80 dark:border-slate-700/80 bg-white dark:bg-slate-900 p-5 shadow-sm"
        >
          <p className="text-xs font-medium text-slate-500 dark:text-slate-400">
            {label}
          </p>
          <p
            className="mt-3 truncate text-2xl font-semibold tracking-tight text-slate-900 dark:text-slate-100 tabular-nums"
            title={String(value)}
          >
            {value ?? "—"}
          </p>
          {caption && (
            <p className="mt-2 text-[10px] text-slate-400">{caption}</p>
          )}
        </div>
      ))}
    </div>
  );
}

export function ResourceState({ resource }) {
  if (resource.error)
    return (
      <div
        role="alert"
        className="my-4 rounded-xl border border-rose-200 dark:border-rose-800 bg-rose-50 dark:bg-rose-950/40 p-4 text-sm whitespace-pre-line text-rose-700 dark:text-rose-300"
      >
        {resource.error}
      </div>
    );
  if (resource.loading && !resource.data)
    return (
      <div
        role="status"
        className="flex items-center gap-2 p-8 text-sm text-slate-400"
      >
        <LoaderCircle className="size-4 animate-spin" />
        Loading banking records…
      </div>
    );
  return null;
}

export function DataTable({
  rows = [],
  columns,
  searchable = true,
  pageSize = 8,
  empty = "No records found.",
  maxHeight,
}) {
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(1);
  const filtered = rows.filter(
    (row) =>
      !search ||
      JSON.stringify(row).toLowerCase().includes(search.toLowerCase()),
  );
  const pages = Math.max(1, Math.ceil(filtered.length / pageSize));
  const actualPage = Math.min(page, pages);
  const visible = filtered.slice(
    (actualPage - 1) * pageSize,
    actualPage * pageSize,
  );
  return (
    <div>
      {searchable && (
        <div className="relative m-5 mb-3 max-w-sm">
          <Search className="absolute top-3 left-3 size-4 text-slate-400" />
          <input
            type="search"
            aria-label="Search table records"
            placeholder="Search records…"
            value={search}
            onChange={(e) => {
              setSearch(e.target.value);
              setPage(1);
            }}
            className={`${inputClass} pl-9`}
          />
        </div>
      )}
      <div className={`overflow-auto ${maxHeight ? "max-h-[440px]" : ""}`}>
        <table className="w-full text-left text-xs">
          <thead className="sticky top-0 z-10 bg-slate-50 dark:bg-slate-950 text-[10px] font-semibold tracking-wide text-slate-500 dark:text-slate-400 uppercase">
            <tr>
              {columns.map((column) => (
                <th key={column.key} className="px-5 py-3.5 whitespace-nowrap">
                  {column.label}
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100 dark:divide-slate-700">
            {visible.map((row, index) => (
              <tr
                key={
                  row.customerid && columns[0]?.key === "customerid"
                    ? row.customerid
                    : index
                }
                className="hover:bg-slate-50/70 dark:hover:bg-slate-950/70"
              >
                {columns.map((column) => (
                  <td
                    key={column.key}
                    className="max-w-sm px-5 py-4 leading-6 break-words text-slate-600 dark:text-slate-300"
                  >
                    {column.render
                      ? column.render(row)
                      : row[column.key] == null
                        ? "—"
                        : String(row[column.key])}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
        {!visible.length && (
          <p className="p-10 text-center text-sm text-slate-400">{empty}</p>
        )}
      </div>
      <div className="flex items-center justify-between gap-3 border-t border-slate-100 dark:border-slate-700 px-5 py-3 text-[11px] text-slate-400">
        <span>
          {filtered.length} records · page {actualPage} / {pages}
        </span>
        <div className="flex gap-2">
          <button
            aria-label="Previous page"
            disabled={actualPage === 1}
            onClick={() => setPage(actualPage - 1)}
            className="rounded-lg border border-slate-200 dark:border-slate-700 p-1.5 hover:bg-slate-50 dark:hover:bg-slate-950 disabled:opacity-30"
          >
            <ChevronLeft className="size-4" />
          </button>
          <button
            aria-label="Next page"
            disabled={actualPage === pages}
            onClick={() => setPage(actualPage + 1)}
            className="rounded-lg border border-slate-200 dark:border-slate-700 p-1.5 hover:bg-slate-50 dark:hover:bg-slate-950 disabled:opacity-30"
          >
            <ChevronRight className="size-4" />
          </button>
        </div>
      </div>
    </div>
  );
}

export function Modal({ title, subtitle, onClose, children, wide = false }) {
  const ref = useRef(null);
  const titleId = useId();
  useEffect(() => {
    const previous = document.activeElement;
    const overflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    ref.current?.focus();
    function onKey(event) {
      if (event.key === "Escape") onClose();
      if (event.key === "Tab") {
        const targets = [
          ...ref.current.querySelectorAll(
            "button:not(:disabled),input:not(:disabled),select:not(:disabled),textarea,a[href]",
          ),
        ].filter((node) => node.getClientRects().length);
        if (!targets.length) {
          event.preventDefault();
          return;
        }
        if (
          event.shiftKey &&
          (document.activeElement === targets[0] ||
            document.activeElement === ref.current)
        ) {
          event.preventDefault();
          targets.at(-1).focus();
        } else if (
          !event.shiftKey &&
          (document.activeElement === targets.at(-1) ||
            document.activeElement === ref.current)
        ) {
          event.preventDefault();
          targets[0].focus();
        }
      }
    }
    document.addEventListener("keydown", onKey);
    return () => {
      document.body.style.overflow = overflow;
      document.removeEventListener("keydown", onKey);
      previous?.focus();
    };
  }, [onClose]);
  return createPortal(
    <div
      className="fixed inset-0 z-40 flex items-center justify-center bg-slate-950/50 p-3 backdrop-blur-sm sm:p-7"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <div
        ref={ref}
        tabIndex={-1}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        className={`flex max-h-[92vh] w-full flex-col rounded-2xl bg-white dark:bg-slate-900 shadow-2xl outline-none ${wide ? "max-w-6xl" : "max-w-2xl"}`}
      >
        <div className="flex shrink-0 items-start justify-between gap-4 border-b border-slate-100 dark:border-slate-700 p-6">
          <div>
            <h2 id={titleId} className="text-lg font-semibold">
              {title}
            </h2>
            {subtitle && (
              <p className="mt-1 text-xs text-slate-400">{subtitle}</p>
            )}
          </div>
          <button
            onClick={onClose}
            aria-label="Close dialog"
            className="rounded-lg p-1.5 text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-800"
          >
            <X className="size-5" />
          </button>
        </div>
        <div className="overflow-y-auto p-6">{children}</div>
      </div>
    </div>,
    document.body,
  );
}

export function WorkflowForm({
  fields,
  initial = {},
  onSubmit,
  busy,
  submitLabel = "Save changes",
  preview,
}) {
  const [values, setValues] = useState(() =>
    Object.fromEntries(
      fields.map((field) => [
        field.name,
        initial[field.name] ?? field.default ?? "",
      ]),
    ),
  );
  const formId = useId();
  function change(field, value) {
    setValues((current) => ({
      ...current,
      [field.name]: value,
      ...(field.onChange?.(value, current) || {}),
    }));
  }
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        onSubmit(values);
      }}
      className="space-y-5"
    >
      <div className="grid gap-4 sm:grid-cols-2">
        {fields
          .filter((field) => !field.when || field.when(values))
          .map((field) => {
            const id = `${formId}-${field.name}`;
            const attrs = {
              id,
              name: field.name,
              required: field.required !== false,
              value: values[field.name],
              onChange: (e) => change(field, e.target.value),
              className: inputClass,
              disabled:
                busy ||
                (typeof field.disabled === "function"
                  ? field.disabled(values)
                  : field.disabled),
              min: field.min,
              max: field.max,
              step: field.step,
              maxLength: field.maxLength,
              pattern: field.pattern,
              placeholder: field.placeholder,
            };
            return (
              <div
                key={field.name}
                className={field.wide ? "sm:col-span-2" : ""}
              >
                <label
                  htmlFor={id}
                  className="mb-1.5 block text-[11px] font-semibold text-slate-600 dark:text-slate-300"
                >
                  {field.label}
                </label>
                {field.type === "select" ? (
                  <select {...attrs}>
                    <option value="">Select…</option>
                    {(typeof field.options === "function"
                      ? field.options(values)
                      : field.options || []
                    ).map((item) => (
                      <option key={item.value} value={item.value}>
                        {item.label}
                      </option>
                    ))}
                  </select>
                ) : field.type === "textarea" ? (
                  <textarea {...attrs} rows={3} />
                ) : (
                  <input {...attrs} type={field.type || "text"} />
                )}
                {field.helper && (
                  <p className="mt-1 text-[10px] leading-5 text-slate-400">
                    {field.helper}
                  </p>
                )}
              </div>
            );
          })}
      </div>
      {preview && preview(values)}
      <button
        type="submit"
        disabled={busy}
        className={`${buttonClass} w-full sm:w-auto`}
      >
        {busy ? (
          <LoaderCircle className="size-4 animate-spin" />
        ) : (
          <ArrowUpRight className="size-4" />
        )}
        {busy ? "Processing…" : submitLabel}
      </button>
    </form>
  );
}

export function CustomerPicker({
  customers = [],
  value,
  onChange,
  label = "Select customer",
  compact = false,
}) {
  const [search, setSearch] = useState("");
  const filtered = customers.filter((c) =>
    `${c.customerid} ${c.firstname} ${c.lastname} ${c.pan_number} ${(c.accounts || []).map((a) => a.accountno).join(" ")}`
      .toLowerCase()
      .includes(search.toLowerCase()),
  );
  return (
    <div className="space-y-2">
      <label className="block text-[11px] font-semibold text-slate-600 dark:text-slate-300">
        {label}
      </label>
      <div className="relative">
        <Search className="absolute top-3 left-3 size-4 text-slate-400" />
        <input
          aria-label="Search customer directory"
          placeholder="Search name, PAN or account number…"
          type="search"
          className={`${inputClass} pl-9`}
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
      </div>
      <select
        aria-label={label}
        className={inputClass}
        value={value}
        onChange={(e) => onChange(e.target.value)}
      >
        <option value="">Choose a real customer…</option>
        {filtered.map((c) => (
          <option key={c.customerid} value={c.customerid}>
            #{c.customerid} · {c.firstname} {c.lastname} | {c.accountcount}{" "}
            accounts (
            {(c.accounts || []).map((a) => a.accountno).join(", ") || "none"}) |{" "}
            {currency(c.totalbalance)} | {c.kyc_status}
          </option>
        ))}
      </select>
      {!compact &&
        value &&
        (() => {
          const c = customers.find(
            (c) => String(c.customerid) === String(value),
          );
          return c ? (
            <div className="flex items-start gap-3 rounded-xl border border-blue-100 dark:border-blue-800 bg-blue-50 dark:bg-blue-950/40 p-3">
              <Landmark className="mt-0.5 size-4 shrink-0 text-blue-600 dark:text-blue-400" />
              <div className="min-w-0 text-xs">
                <p className="font-semibold text-blue-900 dark:text-blue-300">
                  {c.firstname} {c.lastname}{" "}
                  <span className="font-normal text-blue-500 dark:text-blue-400">
                    #{c.customerid}
                  </span>
                </p>
                <p className="mt-1 leading-5 text-blue-600 dark:text-blue-400">
                  Accounts:{" "}
                  {(c.accounts || []).map((a) => a.accountno).join(", ") ||
                    "Not opened"}{" "}
                  · {currency(c.totalbalance)}
                </p>
                <div className="mt-2">
                  <Badge value={c.kyc_status} />
                </div>
              </div>
            </div>
          ) : null;
        })()}
    </div>
  );
}

export function EMIQuote({ values }) {
  const query = useDebounced(
    `${values.principal_amount || ""}|${values.interest_rate || ""}|${values.tenure_months || ""}`,
  );
  const [principal, rate, months] = query.split("|");
  const quote = useResource(
    Number(principal) > 0 && Number(rate) > 0 && Number(months) > 0
      ? `/api/admin/emi-preview?principal=${principal}&rate=${rate}&months=${months}`
      : null,
  );
  return (
    <div className="rounded-xl border border-blue-100 dark:border-blue-800 bg-blue-50 dark:bg-blue-950/40 p-4">
      <p className="text-[10px] font-semibold tracking-wide text-blue-500 dark:text-blue-400 uppercase">
        PostgreSQL EMI preview · fn_calculate_emi
      </p>
      <p className="mt-2 text-2xl font-semibold text-blue-900 dark:text-blue-300">
        {quote.data ? currency(quote.data.emi_amount) : "—"}
      </p>
      <p className="mt-1 text-xs text-blue-500 dark:text-blue-400">
        {quote.error ||
          (quote.loading
            ? "Calculating…"
            : "Monthly installment calculated by the database UDF.")}
      </p>
    </div>
  );
}

export const transactionColumns = [
  {
    key: "transactionid",
    label: "ID",
    render: (row) => `#${row.transactionid}`,
  },
  {
    key: "type",
    label: "Type",
    render: (row) => <Badge value={row.transactiontype || row.type} />,
  },
  { key: "accountno", label: "Account" },
  moneyColumn("amount", "Amount"),
  { key: "paymentmode", label: "Mode" },
  { key: "remarks", label: "Remarks" },
  {
    key: "date",
    label: "Date",
    render: (row) => (
      <span className="whitespace-nowrap">
        {dateTime(row.transactiondate || row.date)}
      </span>
    ),
  },
];
export const loanColumns = [
  { key: "loanid", label: "Loan ID" },
  ownerColumn,
  { key: "branchname", label: "Branch" },
  { key: "loantype", label: "Type" },
  moneyColumn("principalamount", "Principal"),
  { key: "interestrate", label: "Rate %" },
  { key: "tenuremonths", label: "Months" },
  moneyColumn("emi_amount", "Monthly EMI"),
  moneyColumn("outstandingbalance", "Outstanding"),
  statusColumn,
];
export const fdColumns = [
  { key: "fd_id", label: "FD ID" },
  ownerColumn,
  moneyColumn("amount", "Principal"),
  { key: "interestrate", label: "Rate %" },
  { key: "startdate", label: "Start" },
  { key: "enddate", label: "Maturity date" },
  moneyColumn("maturityamount", "Generated maturity"),
  statusColumn,
];
export const accountColumns = [
  { key: "accountno", label: "Account" },
  ownerColumn,
  { key: "accounttype", label: "Type" },
  { key: "branchname", label: "Branch" },
  { key: "ifsc_code", label: "IFSC" },
  moneyColumn("balance", "Balance"),
  { key: "interestrate", label: "Rate %" },
  statusColumn,
];
