import { useSyncExternalStore } from "react";
const SESSION_KEY = "core-banking-session";

export function readSession() {
  try {
    const user = JSON.parse(localStorage.getItem(SESSION_KEY));
    if (
      user &&
      ["Admin", "Customer"].includes(user.role) &&
      Number.isInteger(Number(user.id)) &&
      Number(user.id) > 0
    )
      return user;
  } catch {
    /* Malformed or unavailable storage behaves as signed out. */
  }
  return null;
}

export function saveSession(user) {
  localStorage.setItem(SESSION_KEY, JSON.stringify(user));
  localStorage.setItem("role", user.role);
  localStorage.setItem("id", String(user.id));
  if (user.role === "Customer")
    localStorage.setItem("last_customer_id", String(user.id));
  window.dispatchEvent(new Event("core-session"));
}

export function clearSession() {
  localStorage.removeItem(SESSION_KEY);
  localStorage.removeItem("role");
  localStorage.removeItem("id");
  window.dispatchEvent(new Event("core-session"));
}

function subscribe(callback) {
  window.addEventListener("core-session", callback);
  window.addEventListener("storage", callback);
  return () => {
    window.removeEventListener("core-session", callback);
    window.removeEventListener("storage", callback);
  };
}
export function useSession() {
  useSyncExternalStore(
    subscribe,
    () => localStorage.getItem(SESSION_KEY),
    () => null,
  );
  return readSession();
}
