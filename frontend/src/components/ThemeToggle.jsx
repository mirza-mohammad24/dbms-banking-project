import { Moon, Sun } from "lucide-react";
import { toggleTheme, useTheme } from "../lib/theme";

export default function ThemeToggle() {
  const theme = useTheme();
  const dark = theme === "dark";
  const label = `Switch to ${dark ? "light" : "dark"} mode`;
  const Icon = dark ? Sun : Moon;
  return (
    <button
      type="button"
      aria-label={label}
      aria-pressed={dark}
      title={label}
      onClick={toggleTheme}
      className="inline-flex shrink-0 items-center gap-2 rounded-xl border border-slate-200 bg-white px-3 py-2 text-xs font-medium text-slate-600 transition hover:bg-slate-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-500 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-200 dark:hover:bg-slate-800"
    >
      <Icon aria-hidden="true" className="size-4" />
      <span className="hidden sm:inline">
        {dark ? "Light mode" : "Dark mode"}
      </span>
    </button>
  );
}
