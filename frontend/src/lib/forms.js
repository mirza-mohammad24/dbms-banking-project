import { currency } from "./api";
import { choices, option } from "../components/BankingUI";

export const text = (name, label, extra = {}) => ({ name, label, ...extra });
export const number = (name, label, extra = {}) =>
  text(name, label, { type: "number", min: "0.01", step: "0.01", ...extra });
export const select = (name, label, options, extra = {}) =>
  text(name, label, { type: "select", options, ...extra });
export const accountOptions = (accounts) =>
  accounts.map((a) =>
    option(
      a.accountno,
      `#${a.accountno} · ${a.accounttype} · ${currency(a.balance)} · ${a.status}`,
    ),
  );
export const customerOptions = (customers) =>
  customers.map((c) =>
    option(
      c.customerid,
      `#${c.customerid} · ${c.firstname} ${c.lastname} · ${(c.accounts || []).map((a) => a.accountno).join(", ") || "No accounts"}`,
    ),
  );
export const branchOptions = (branches) =>
  branches.map((b) =>
    option(b.branchid, `${b.branchname} · ${b.city} · ${b.ifsc_code}`),
  );
export const modes = choices([
  "UPI",
  "NEFT",
  "RTGS",
  "IMPS",
  "Cash",
  "Internal",
]);
export const accountStates = ["Active", "Dormant", "Frozen", "Closed"];
export function plusDays(day, count) {
  const date = new Date(`${day}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + count);
  return date.toISOString().slice(0, 10);
}
export const nullable = (values) =>
  Object.fromEntries(
    Object.entries(values).map(([key, value]) => [
      key,
      value === "" ? null : value,
    ]),
  );

export function beneficiaryFields(banks) {
  return [
    text("beneficiary_name", "Beneficiary name", { maxLength: 100 }),
    number("linked_account_no", "Linked account number", { min: 1, step: 1 }),
    select("ifsc_code", "Bank / IFSC directory", [
      ...banks.map((b) =>
        option(b.ifsc_code, `${b.ifsc_code} · ${b.bankname}`),
      ),
      option("__new__", "+ Register a new IFSC"),
    ]),
    text("new_ifsc", "New IFSC code", {
      when: (v) => v.ifsc_code === "__new__",
      maxLength: 15,
      pattern: "[A-Z0-9]+",
    }),
    text("bank_name", "Bank name for new IFSC", {
      when: (v) => v.ifsc_code === "__new__",
      maxLength: 100,
    }),
    number("max_transfer_limit", "Daily transfer limit (INR)", {
      default: "100000.00",
    }),
  ];
}
export function beneficiaryPayload(values) {
  const { new_ifsc, ...payload } = values;
  return {
    ...payload,
    ifsc_code: payload.ifsc_code === "__new__" ? new_ifsc : payload.ifsc_code,
    bank_name: payload.ifsc_code === "__new__" ? payload.bank_name : null,
  };
}

export const customerFields = [
  text("first_name", "First name", { maxLength: 50 }),
  text("last_name", "Last name", { maxLength: 50 }),
  select("gender", "Gender", choices(["Male", "Female", "Other"])),
  number("age", "Age", { min: 18, max: 120, step: 1 }),
  text("address", "Address", { type: "textarea", maxLength: 200, wide: true }),
  text("phone", "Phone", { maxLength: 15 }),
  text("email", "Email address", { type: "email", maxLength: 100 }),
  text("pan_number", "PAN number", {
    maxLength: 10,
    pattern: "[A-Z]{5}[0-9]{4}[A-Z]",
    placeholder: "ABCDE1234F",
  }),
  select(
    "kyc_status",
    "KYC status",
    choices(["Pending", "Approved", "Rejected"]),
    { default: "Pending" },
  ),
];
