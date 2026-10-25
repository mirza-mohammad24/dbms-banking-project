import axios from "axios";

export const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL || "http://localhost:8000",
  timeout: 20000,
});

export function apiError(error) {
  const detail = error.response?.data?.detail;
  if (Array.isArray(detail))
    return detail
      .map(
        (item) => `${item.loc?.slice(1).join(".") || "Request"}: ${item.msg}`,
      )
      .join(" · ");
  if (typeof detail === "string") return detail;
  return (
    error.response?.data?.message ||
    (error.code === "ECONNABORTED"
      ? "The request timed out. Refresh the activity before retrying the operation."
      : "Unable to reach the banking API. Check that the backend is running on port 8000.")
  );
}

export const currency = (value = 0) =>
  new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(Number(value));

export const compactCurrency = (value) =>
  `₹${new Intl.NumberFormat("en-IN", {
    notation: "compact",
    maximumFractionDigits: 1,
  }).format(Number(value))}`;

export function dateTime(value) {
  if (!value) return "Not recorded";
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? value
    : new Intl.DateTimeFormat("en-IN", {
        day: "2-digit",
        month: "short",
        year: "numeric",
        hour: "2-digit",
        minute: "2-digit",
      }).format(date);
}
