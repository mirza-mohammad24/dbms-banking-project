"""Streamlit interface for the Core Banking PostgreSQL lab project.

Start with: uv run streamlit run app.py
Identity and portal selection simulate a local lab login; they are not an
authentication system. Banking rules and monetary calculations stay in SQL.
"""

from contextlib import closing
from decimal import Decimal

import pandas as pd
import psycopg2
import streamlit as st


DB_CONFIG = {
    "dbname": "banking_db",
    "user": "postgres",
    "password": "admin",
    "host": "localhost",
    "port": "5432",
    "connect_timeout": 5,
    "application_name": "core_banking_streamlit",
    "options": "-c search_path=pg_catalog,public -c statement_timeout=15000 -c lock_timeout=5000",
}
MAX_ID = 2_147_483_647
CUSTOMER_PORTAL = "Customer Self-Service Portal"
ADMIN_PORTAL = "Bank Staff / Admin Portal"


def connect_database():
    """Return a fresh connection; the caller always closes it.

    Autocommit is essential for sp_transfer_funds, which explicitly COMMITs.
    Each SELECT or CALL is isolated. Other procedures remain atomic within
    their single CALL, and PostgreSQL rolls back the statement on failure.
    Do not use a psycopg2 connection context that starts an enclosing transaction.
    """
    connection = psycopg2.connect(**DB_CONFIG)
    connection.autocommit = True
    return connection


def fetch_dataframe(query: str, params: tuple = ()) -> pd.DataFrame | None:
    """Execute a parameterized read and build a pandas table from its result."""
    try:
        with closing(connect_database()) as connection:
            with connection.cursor() as cursor:
                cursor.execute(query, params)
                return pd.DataFrame(
                    cursor.fetchall(), columns=[column.name for column in cursor.description]
                )
    except Exception as e:
        st.error(f"Transaction Failed: {e}")
        return None


def execute_action(query: str, params: tuple, success_message: str) -> bool:
    """Only report success after the CALL completed and its commit succeeded."""
    try:
        with closing(connect_database()) as connection:
            with connection.cursor() as cursor:
                cursor.execute(query, params)
        # A fresh render reloads balances, passbook, summary, and audit records.
        st.session_state["transaction_success"] = success_message
        return True
    except Exception as e:
        # Autocommit + closing discards the failed statement's connection.
        # No aborted transaction is shared with the next action or Streamlit user.
        st.error(f"Transaction Failed: {e}")
        return False


def inr(amount) -> str:
    return f"₹{Decimal(str(amount)):,.2f}"


def show_table(frame: pd.DataFrame | None, empty_message: str) -> None:
    if frame is None:
        return  # The database helper has already displayed the error.
    if frame.empty:
        st.info(empty_message)
    else:
        st.dataframe(frame, hide_index=True, width="stretch")


def render_customer_portal() -> None:
    st.header("Customer Self-Service")
    st.caption("Your accounts, transactions, and borrowing in one place.")

    with st.sidebar:
        st.divider()
        st.subheader("Customer identity")
        identity_type = st.selectbox(
            "Identify customer by", ["Customer ID", "Account number"], key="identity_type"
        )
        if identity_type == "Customer ID":
            identifier = st.number_input(
                "Customer ID", min_value=1, max_value=MAX_ID, value=1, step=1,
                key="customer_id_input",
            )
        else:
            identifier = st.number_input(
                "Account number", min_value=1, max_value=MAX_ID, value=100001, step=1,
                key="account_identity_input",
            )

    if identity_type == "Customer ID":
        customer = fetch_dataframe(
            "SELECT CustomerID, FirstName, LastName, KYC_Status FROM public.Customer "
            "WHERE CustomerID = %s", (identifier,),
        )
    else:
        customer = fetch_dataframe(
            "SELECT c.CustomerID, c.FirstName, c.LastName, c.KYC_Status "
            "FROM public.Customer c JOIN public.Account a ON a.CustomerID = c.CustomerID "
            "WHERE a.AccountNo = %s", (identifier,),
        )
    if customer is None:
        return
    if customer.empty:
        st.info("No customer found. Check the selected ID or account number.")
        return

    owner = customer.iloc[0]
    customer_id = int(owner["customerid"])
    st.subheader(f"{owner['firstname']} {owner['lastname']}")
    st.caption(f"Customer ID {customer_id} · KYC: {owner['kyc_status'] or 'Not set'}")

    accounts = fetch_dataframe(
        'SELECT a.AccountNo AS "Account No", a.AccountType AS "Type", '
        'b.BranchName AS "Branch", a.Balance AS "Balance (INR)", a.Status AS "Status" '
        "FROM public.Account a JOIN public.Branch b ON b.BranchID = a.BranchID "
        "WHERE a.CustomerID = %s ORDER BY a.AccountNo", (customer_id,),
    )
    worth = fetch_dataframe(
        "SELECT public.fn_customer_net_worth(%s) AS net_worth", (customer_id,),
    )
    balance_column, worth_column, count_column = st.columns(3)
    if accounts is not None:
        balance_column.metric("Account balances", inr(sum(accounts["Balance (INR)"], Decimal(0))))
        count_column.metric("Accounts", len(accounts))
    if worth is not None and not worth.empty:
        worth_column.metric("Net worth", inr(worth.iloc[0]["net_worth"]))
    st.caption("Net worth includes account balances and Active FD principal, less outstanding loans.")

    st.subheader("Your accounts")
    show_table(accounts, "This customer has no accounts yet.")

    st.divider()
    st.subheader("Passbook")
    passbook = fetch_dataframe(
        'SELECT p.AccountNo AS "Account No", p.Name AS "Name", p.BranchName AS "Branch", '
        'p.Date AS "Date", p.Type AS "Type", p.Amount AS "Amount (INR)", p.Remarks AS "Remarks" '
        "FROM public.vw_customer_passbook p JOIN public.Account a ON a.AccountNo = p.AccountNo "
        "WHERE a.CustomerID = %s "
        "ORDER BY p.Date DESC NULLS LAST, p.AccountNo, p.Type, p.Amount, p.Remarks", (customer_id,),
    )
    show_table(passbook, "No transactions recorded for this customer.")

    st.divider()
    st.subheader("Payments")
    loans = fetch_dataframe(
        'SELECT LoanID AS "Loan ID", LoanType AS "Type", EMI_Amount AS "EMI (INR)", '
        'OutstandingBalance AS "Outstanding (INR)", Status AS "Status" '
        "FROM public.Loan WHERE CustomerID = %s ORDER BY LoanID", (customer_id,),
    )
    with st.expander("Your loans", expanded=False):
        show_table(loans, "This customer has no loans.")
    if accounts is None or accounts.empty:
        st.info("An account is required to transfer funds or pay an EMI.")
        return

    # Scope sender choices to this customer, while retaining Dormant/Frozen
    # accounts so the database can visibly demonstrate its status validation.
    account_numbers = [int(number) for number in accounts["Account No"]]
    # Identity-specific form keys prevent an old customer's sender selection
    # from carrying into a newly selected customer.
    transfer_column, emi_column = st.columns(2, gap="large")
    with transfer_column:
        with st.form(f"transfer_form_{customer_id}"):
            st.subheader("Fund transfer")
            sender = st.selectbox("Sender Account", account_numbers, key=f"sender_{customer_id}")
            receiver = st.number_input(
                "Receiver Account", min_value=1, max_value=MAX_ID, value=100003,
                step=1, key=f"receiver_{customer_id}",
            )
            amount = st.number_input(
                "Amount (INR)", min_value=0.01, max_value=9_999_999_999_999.99,
                value=1000.00, step=0.01, format="%.2f", key=f"amount_{customer_id}",
            )
            mode = st.selectbox(
                "Mode", ["Internal", "UPI", "NEFT", "RTGS", "IMPS", "Cash"],
                key=f"mode_{customer_id}",
            )
            remarks = st.text_input("Remarks", max_chars=200, key=f"remarks_{customer_id}")
            transfer_submitted = st.form_submit_button("Transfer Funds", type="primary")
        if transfer_submitted:
            # Send Decimal to psycopg2; monetary calculations remain in PostgreSQL.
            transfer_amount = Decimal(str(amount)).quantize(Decimal("0.01"))
            if execute_action(
                "CALL public.sp_transfer_funds(%s, %s, %s, %s, %s)",
                (sender, receiver, transfer_amount, mode, remarks or None),
                f"Transfer committed: {inr(transfer_amount)} from {sender} to {receiver}.",
            ):
                st.rerun()

    with emi_column:
        with st.form(f"emi_form_{customer_id}"):
            st.subheader("Pay loan EMI")
            default_loan = int(loans.iloc[0]["Loan ID"]) if loans is not None and not loans.empty else 2001
            loan_id = st.number_input(
                "Loan ID", min_value=1, max_value=MAX_ID, value=default_loan,
                step=1, key=f"loan_{customer_id}",
            )
            paying_account = st.selectbox(
                "Account No", account_numbers, key=f"emi_account_{customer_id}"
            )
            st.caption("The database calculates the installment and checks account and loan ownership.")
            emi_submitted = st.form_submit_button("Pay EMI", type="primary")
        if emi_submitted and execute_action(
            "CALL public.sp_pay_loan_emi(%s, %s, %s)",
            (customer_id, loan_id, paying_account),
            f"EMI payment committed for loan {loan_id}. Balances and repayment records updated.",
        ):
            st.rerun()


@st.fragment(run_every="10s")
def render_audit_log() -> None:
    """Refresh audit records independently while the staff portal is open."""
    st.subheader("Live System Audit Log")
    st.caption("Latest 50 events · refreshes every 10 seconds.")
    audit = fetch_dataframe(
        'SELECT LogID AS "Log ID", LogDate AS "Date", TableName AS "Table", '
        'RecordID AS "Record ID", ActionType AS "Action", Description AS "Description" '
        "FROM public.Audit_Log ORDER BY LogDate DESC NULLS LAST, LogID DESC LIMIT 50"
    )
    show_table(audit, "No audit events recorded yet.")


def render_admin_portal() -> None:
    st.header("Bank Staff / Admin")
    st.caption("Branch performance, batch operations, and database audit events.")
    st.subheader("Financial Summary")
    summary = fetch_dataframe(
        'SELECT BranchID AS "Branch ID", BranchName AS "Branch", '
        'total_active_accounts AS "Active Accounts", '
        'total_loan_outstanding AS "Loan Outstanding (INR)", '
        'total_fd_maturity_amounts AS "FD Maturity Amounts (INR)" '
        "FROM public.vw_branch_financial_summary ORDER BY BranchID"
    )
    show_table(summary, "No branches available.")
    st.caption("Active FD maturity values use the customer's primary account branch for reporting.")

    st.divider()
    st.subheader("End-of-Month Batch Processing")
    interest_column, maturity_column = st.columns(2, gap="large")
    with interest_column:
        st.markdown("**Monthly savings interest**")
        st.caption("Credit eligible Active Savings accounts once per calendar month.")
        if st.button("Credit Savings Interest", type="primary", key="credit_interest"):
            if execute_action(
                "CALL public.sp_batch_credit_savings_interest()", (),
                "Savings interest batch committed. Eligible accounts and audit records are up to date.",
            ):
                st.rerun()
    with maturity_column:
        st.markdown("**Fixed deposit maturity**")
        st.caption("Pay due Active FDs into the owner's primary Active Savings account.")
        if st.button("Mature Fixed Deposits", type="primary", key="mature_fds"):
            if execute_action(
                "CALL public.sp_batch_mature_fixed_deposits()", (),
                "Fixed deposit maturity batch committed. Due deposits and audit records are up to date.",
            ):
                st.rerun()

    st.divider()
    render_audit_log()


def main() -> None:
    st.set_page_config(page_title="Core Banking", page_icon="🏦", layout="wide")
    st.title("Core Banking")
    st.caption("Banking & Transaction Management System · BCSE302P")
    with st.sidebar:
        st.header("Banking workspace")
        role = st.selectbox("Role Selector", [CUSTOMER_PORTAL, ADMIN_PORTAL], key="portal_role")
        st.caption("Local lab demo · role and identity selection simulate a login.")
        st.button("Refresh data", key="refresh_data")

    message = st.session_state.pop("transaction_success", None)
    if message:
        st.success(message)
    if role == CUSTOMER_PORTAL:
        render_customer_portal()
    else:
        render_admin_portal()


if __name__ == "__main__":
    main()
