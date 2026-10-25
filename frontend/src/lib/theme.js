import { useSyncExternalStore } from "react";

const STORAGE_KEY = "core-banking-theme";
const systemTheme = window.matchMedia("(prefers-color-scheme: dark)");
let preference;
try {
  preference = localStorage.getItem(STORAGE_KEY);
} catch {
  // The toggle still works when browser storage is unavailable.
}
let theme = ["light", "dark"].includes(preference)
  ? preference
  : systemTheme.matches
    ? "dark"
    : "light";
const listeners = new Set();

function applyTheme() {
  document.documentElement.classList.toggle("dark", theme === "dark");
  document.documentElement.style.colorScheme = theme;
  document
    .querySelector('meta[name="theme-color"]')
    ?.setAttribute("content", theme === "dark" ? "#020617" : "#f8fafc");
}
function publish() {
  applyTheme();
  listeners.forEach((listener) => listener());
}
applyTheme();

systemTheme.addEventListener("change", () => {
  if (!["light", "dark"].includes(preference)) {
    theme = systemTheme.matches ? "dark" : "light";
    publish();
  }
});
window.addEventListener("storage", (event) => {
  if (event.key === STORAGE_KEY || event.key === null) {
    preference = event.key === null ? null : event.newValue;
    theme = ["light", "dark"].includes(preference)
      ? preference
      : systemTheme.matches
        ? "dark"
        : "light";
    publish();
  }
});

export function toggleTheme() {
  theme = theme === "dark" ? "light" : "dark";
  preference = theme;
  try {
    localStorage.setItem(STORAGE_KEY, theme);
  } catch {
    // Keep the in-memory preference for this session.
  }
  publish();
}
function subscribe(listener) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}
export function useTheme() {
  return useSyncExternalStore(
    subscribe,
    () => theme,
    () => "light",
  );
}
