import {
  Bar,
  BarChart,
  Cell,
  CartesianGrid,
  Legend,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import {
  DataTable,
  Metrics,
  Panel,
  accountColumns,
  moneyColumn,
} from "./BankingUI";
import { compactCurrency, currency } from "../lib/api";

const colors = ["#2563eb", "#38bdf8", "#0d9488", "#818cf8", "#f59e0b"];
function Distribution({ title, rows }) {
  return (
    <Panel title={title}>
      <div className="h-64 p-5" role="img" aria-label={title}>
        <ResponsiveContainer width="100%" height="100%">
          <PieChart>
            <Pie
              data={rows}
              dataKey="value"
              nameKey="name"
              innerRadius={48}
              outerRadius={72}
              paddingAngle={3}
              isAnimationActive={false}
            >
              {rows.map((row, index) => (
                <Cell key={row.name} fill={colors[index % colors.length]} />
              ))}
            </Pie>
            <Tooltip
              contentStyle={{
                backgroundColor: "var(--chart-surface)",
                color: "var(--chart-text)",
                border: "1px solid var(--chart-grid)",
                borderRadius: 12,
              }}
              itemStyle={{ color: "var(--chart-text)" }}
            />
            <Legend
              iconType="circle"
              iconSize={7}
              wrapperStyle={{ fontSize: 10, color: "var(--chart-text)" }}
            />
          </PieChart>
        </ResponsiveContainer>
      </div>
    </Panel>
  );
}
export default function AdminAnalytics({ data }) {
  if (!data) return null;
  const loanTypes = Object.values(
    data.loans_by_type_status.reduce(
      (acc, row) => ({
        ...acc,
        [row.loantype]: {
          name: row.loantype,
          value: (acc[row.loantype]?.value || 0) + Number(row.count),
        },
      }),
      {},
    ),
  );
  return (
    <>
      <Metrics
        items={[
          [
            "Customers",
            data.table_counts.Customer,
            `${data.table_counts.Branch} branches · ${data.table_counts.Employee} officials`,
          ],
          [
            "CASA deposits",
            compactCurrency(data.total_deposits),
            "Non-closed account balances",
          ],
          [
            "Active loan book",
            compactCurrency(data.active_loan_book),
            "Approved, active, and defaulted debt",
          ],
          [
            "Active FD book",
            compactCurrency(data.active_fd_book),
            "Principal currently invested",
          ],
        ]}
      />
      <Panel
        title="Branch deposits vs loan exposure"
        subtitle="View-backed loan totals with independently aggregated account deposits."
      >
        <div
          className="h-80 p-5"
          role="img"
          aria-label="Branch deposits versus loans"
        >
          <ResponsiveContainer width="100%" height="100%">
            <BarChart
              data={data.branches.map((row) => ({
                ...row,
                city: row.branchname.split(" ")[0],
                deposits: Number(row.total_deposits),
                loans: Number(row.total_loan_outstanding),
              }))}
              barGap={5}
            >
              <CartesianGrid
                vertical={false}
                stroke="var(--chart-grid)"
                strokeDasharray="3 4"
              />
              <XAxis
                dataKey="city"
                tick={{ fontSize: 10, fill: "var(--chart-tick)" }}
                axisLine={false}
                tickLine={false}
              />
              <YAxis
                tickFormatter={compactCurrency}
                width={65}
                tick={{ fontSize: 10, fill: "var(--chart-tick)" }}
                axisLine={false}
                tickLine={false}
              />
              <Tooltip
                formatter={(value) => currency(value)}
                labelFormatter={(_, payload) =>
                  payload?.[0]?.payload?.branchname
                }
                contentStyle={{
                  borderRadius: 12,
                  fontSize: 12,
                  backgroundColor: "var(--chart-surface)",
                  color: "var(--chart-text)",
                  border: "1px solid var(--chart-grid)",
                }}
                labelStyle={{ color: "var(--chart-text)" }}
                cursor={{ fill: "var(--chart-grid)", fillOpacity: 0.3 }}
              />
              <Legend
                wrapperStyle={{ fontSize: 10, color: "var(--chart-text)" }}
                iconType="circle"
                iconSize={7}
              />
              <Bar
                dataKey="deposits"
                name="Account deposits"
                fill="#38bdf8"
                radius={[4, 4, 0, 0]}
                isAnimationActive={false}
              />
              <Bar
                dataKey="loans"
                name="Loan outstanding"
                fill="#2563eb"
                radius={[4, 4, 0, 0]}
                isAnimationActive={false}
              />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </Panel>
      <div className="grid gap-5 xl:grid-cols-2">
        <Distribution
          title="Accounts by product"
          rows={data.accounts_by_type.map((row) => ({
            ...row,
            value: Number(row.value),
          }))}
        />
        <Distribution title="Loans by purpose" rows={loanTypes} />
      </div>
      <Panel
        title="Database footprint"
        subtitle="Live row counts across all twelve normalized tables."
      >
        <div className="grid grid-cols-2 gap-3 p-5 sm:grid-cols-3 xl:grid-cols-6">
          {Object.entries(data.table_counts).map(([table, count]) => (
            <div
              key={table}
              className="rounded-xl border border-slate-100 dark:border-slate-700 bg-slate-50 dark:bg-slate-950 p-3"
            >
              <p className="text-lg font-semibold tabular-nums">{count}</p>
              <p className="mt-1 text-[9px] text-slate-400">{table}</p>
            </div>
          ))}
        </div>
      </Panel>
      <Panel
        title="Branch financial view"
        subtitle="vw_branch_financial_summary · FD attribution follows the primary-account branch."
      >
        <DataTable
          rows={data.branches}
          columns={[
            { key: "branchid", label: "ID" },
            { key: "branchname", label: "Branch" },
            { key: "total_active_accounts", label: "Active accounts" },
            moneyColumn("total_deposits", "Deposits"),
            moneyColumn("total_loan_outstanding", "Loans outstanding"),
            moneyColumn("total_fd_maturity_amounts", "FD maturity total"),
          ]}
        />
      </Panel>
      <Panel
        title="Active Vellore account view"
        subtitle="vw_active_vellore_accounts · row-restricting, updatable view with CHECK OPTION."
      >
        <DataTable
          rows={data.vellore_accounts}
          columns={accountColumns.filter(
            (c) => !["customername", "branchname", "ifsc_code"].includes(c.key),
          )}
        />
      </Panel>
      <div className="grid items-start gap-5 xl:grid-cols-2">
        <Panel title="Loan type & status distribution">
          <DataTable
            rows={data.loans_by_type_status}
            columns={[
              { key: "loantype", label: "Product" },
              { key: "status", label: "Status" },
              { key: "count", label: "Loans" },
              moneyColumn("outstanding", "Outstanding"),
            ]}
          />
        </Panel>
        <Panel
          title="Transaction volume by payment mode"
          subtitle="Gross event volume, not net cash flow."
        >
          <DataTable
            rows={data.volume_by_mode}
            columns={[
              { key: "name", label: "Payment mode" },
              { key: "count", label: "Events" },
              moneyColumn("volume", "Gross volume"),
            ]}
          />
        </Panel>
      </div>
    </>
  );
}
