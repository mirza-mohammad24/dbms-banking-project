import {
  Badge,
  DataTable,
  Metrics,
  Panel,
  ResourceState,
  accountColumns,
  fdColumns,
  loanColumns,
  moneyColumn,
  transactionColumns,
} from "./BankingUI";
import { currency } from "../lib/api";
import { useResource } from "../lib/hooks";

export default function Customer360({ customerId, revision }) {
  const resource = useResource(
    `/api/admin/customer/${customerId}/full-360`,
    revision,
  );
  const data = resource.data;
  return (
    <div className="space-y-5">
      <ResourceState resource={resource} />
      {data && (
        <>
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <p className="text-lg font-semibold">
                {data.profile.firstname} {data.profile.lastname}
              </p>
              <p className="mt-1 text-xs text-slate-400">
                Customer #{customerId} · PAN {data.profile.pan_number} ·{" "}
                {data.profile.email}
              </p>
            </div>
            <Badge value={data.profile.kyc_status} />
          </div>
          <Metrics
            items={[
              ["Net worth", currency(data.net_worth)],
              ["Liquid balance", currency(data.liquid_balance)],
              ["Active FDs", currency(data.fd_principal)],
              ["Outstanding loans", currency(data.loan_outstanding)],
            ]}
          />
          <div className="rounded-xl bg-slate-50 dark:bg-slate-950 p-4 text-xs leading-7 text-slate-500 dark:text-slate-400">
            <p>
              {data.profile.gender} · Age {data.profile.age} · Phone{" "}
              {data.profile.phone}
            </p>
            <p>{data.profile.address}</p>
          </div>
          <Panel title="Account ownership">
            <DataTable rows={data.accounts} columns={accountColumns} />
          </Panel>
          <Panel title="Loan portfolio">
            <DataTable rows={data.loans} columns={loanColumns} />
          </Panel>
          <Panel title="Fixed deposits">
            <DataTable rows={data.fixed_deposits} columns={fdColumns} />
          </Panel>
          <Panel title="Saved beneficiaries">
            <DataTable
              rows={data.beneficiaries}
              columns={[
                { key: "beneficiaryid", label: "ID" },
                { key: "beneficiaryname", label: "Name" },
                { key: "linkedaccountno", label: "Linked account" },
                { key: "bankname", label: "Bank" },
                { key: "ifsc_code", label: "IFSC" },
                moneyColumn("maxtransferlimit", "Daily limit"),
              ]}
            />
          </Panel>
          <Panel title="Transaction history">
            <DataTable rows={data.transactions} columns={transactionColumns} />
          </Panel>
        </>
      )}
    </div>
  );
}
