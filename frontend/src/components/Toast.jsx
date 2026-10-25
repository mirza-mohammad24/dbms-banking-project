import { useEffect } from "react";
import Icon from "./Icon";

export default function Toast({ toast, onClose }) {
  useEffect(() => {
    if (!toast) return;
    const timer = setTimeout(onClose, toast.type === "error" ? 12000 : 6500);
    return () => clearTimeout(timer);
  }, [toast, onClose]);
  if (!toast) return null;
  const error = toast.type === "error";
  return (
    <div
      className="fixed top-6 right-4 left-4 z-50 mx-auto max-w-lg sm:right-6 sm:left-auto"
      role={error ? "alert" : "status"}
    >
      <div
        className={`flex items-start gap-3 rounded-2xl border bg-white dark:bg-slate-900 p-4 shadow-xl shadow-slate-900/10 ${error ? "border-rose-200 dark:border-rose-800" : "border-emerald-200 dark:border-emerald-800"}`}
      >
        <span
          className={`rounded-full p-1.5 ${error ? "bg-rose-50 dark:bg-rose-950/40 text-rose-600 dark:text-rose-400" : "bg-emerald-50 dark:bg-emerald-950/40 text-emerald-600 dark:text-emerald-400"}`}
        >
          <Icon name={error ? "close" : "check"} className="size-4" />
        </span>
        <div className="min-w-0 flex-1">
          <p className="text-sm font-semibold text-slate-900 dark:text-slate-100">
            {error ? "Unable to complete request" : "Request completed"}
          </p>
          <p className="mt-1 text-sm leading-6 break-words whitespace-pre-line text-slate-600 dark:text-slate-300">
            {toast.message}
          </p>
        </div>
        <button
          onClick={onClose}
          aria-label="Dismiss notification"
          className="rounded-md p-1 text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-800 hover:text-slate-700 dark:hover:text-slate-300"
        >
          <Icon name="close" className="size-4" />
        </button>
      </div>
    </div>
  );
}
