"""Append realistic fictional Indian banking fixtures in one transaction.

Run: uv run python seed_bulk_data.py
Each successful run adds 100 customers, 150 accounts, 50 loans, 500 historical
transaction events, and 40 FDs. Existing data is retained. Balances/outstanding
amounts are opening snapshots; historical events are not replayed as postings
and do not claim to be a complete or balanced double-entry ledger.
"""

from datetime import datetime, time, timedelta
from decimal import Decimal, ROUND_HALF_UP
import random
import re
import sys

from faker import Faker
import psycopg2
from psycopg2 import sql
from psycopg2.extras import execute_values


fake = Faker("en_IN")
CENT = Decimal("0.01")
EXPECTED = {
    "Customer": 100,
    "Account": 150,
    "Loan": 50,
    "Transaction_History": 500,
    "Fixed_Deposit": 40,
}


def money(value: Decimal) -> Decimal:
    return value.quantize(CENT, rounding=ROUND_HALF_UP)


def unique_value(factory, used: set[str]) -> str:
    """Check both stored values and values generated earlier in this run."""
    for _ in range(1000):
        candidate = factory()
        if candidate not in used:
            used.add(candidate)
            return candidate
    raise RuntimeError("Unable to generate a unique phone, email, or PAN")


def next_id(cursor, table: str, column: str) -> int:
    cursor.execute(sql.SQL("SELECT COALESCE(MAX({}), 0) + 1 FROM {}.{}").format(
        sql.Identifier(column.lower()), sql.Identifier("public"), sql.Identifier(table.lower())
    ))
    return cursor.fetchone()[0]


def table_counts(cursor) -> dict[str, int]:
    counts = {}
    for table in EXPECTED:
        cursor.execute(sql.SQL("SELECT COUNT(*) FROM public.{}").format(sql.Identifier(table.lower())))
        counts[table] = cursor.fetchone()[0]
    return counts


def insert_rows(cursor, table: str, columns: tuple[str, ...], rows: list[tuple], returning: str) -> None:
    statement = sql.SQL("INSERT INTO public.{} ({}) VALUES %s RETURNING {}").format(
        sql.Identifier(table.lower()),
        sql.SQL(", ").join(sql.Identifier(column.lower()) for column in columns),
        sql.Identifier(returning.lower()),
    ).as_string(cursor)
    inserted = execute_values(cursor, statement, rows, page_size=250, fetch=True)
    # execute_values.rowcount reports only the last page, so use RETURNING.
    if len(inserted) != EXPECTED[table]:
        raise RuntimeError(f"{table}: expected {EXPECTED[table]} inserts, got {len(inserted)}")


def seed_data(cursor) -> tuple[dict[str, int], dict[str, int], dict[str, tuple[int, int]]]:
    rng = random.Random()
    # Brief write locks make MAX+1 allocation and before/after verification safe
    # against concurrent seeders or manual inserts. SELECT dashboards still work.
    # Existing customer/account records and SERIAL sequences are never reset.
    cursor.execute("SET LOCAL lock_timeout = '5s'")
    cursor.execute("SET LOCAL statement_timeout = '30s'")
    cursor.execute(
        "LOCK TABLE public.Customer, public.Account, public.Loan, "
        "public.Transaction_History, public.Fixed_Deposit IN SHARE ROW EXCLUSIVE MODE"
    )
    cursor.execute("SELECT CURRENT_TIMESTAMP::timestamp")
    now = cursor.fetchone()[0]
    today = now.date()

    # Fetch infrastructure instead of assuming any branch IDs, cities, or IFSCs.
    cursor.execute("SELECT Pincode, City, State FROM public.Postal_Directory ORDER BY Pincode")
    postal = {pincode: (city, state) for pincode, city, state in cursor.fetchall()}
    cursor.execute("SELECT IFSC_Code, BankName FROM public.Bank_Directory ORDER BY IFSC_Code")
    banks = dict(cursor.fetchall())
    cursor.execute("SELECT BranchID, Pincode, IFSC_Code FROM public.Branch ORDER BY BranchID")
    branches = cursor.fetchall()
    if not postal or not banks or not branches:
        raise RuntimeError("Seed the postal directory, bank directory, and branches first")
    if any(pincode not in postal or ifsc not in banks for _, pincode, ifsc in branches):
        raise RuntimeError("Every existing branch must have a valid postal and bank directory entry")
    print(f"Infrastructure loaded: {len(branches)} branches, {len(postal)} postal codes, {len(banks)} IFSC entries")
    # New Account/Loan rows link to these branches; postal and bank directory
    # relationships are reused through Branch (these new tables have no IFSC FK).

    before = table_counts(cursor)
    first_customer = next_id(cursor, "Customer", "CustomerID")
    first_account = next_id(cursor, "Account", "AccountNo")
    first_loan = next_id(cursor, "Loan", "LoanID")
    first_fd = next_id(cursor, "Fixed_Deposit", "FD_ID")
    cursor.execute("SELECT Phone, Email, PAN_Number FROM public.Customer")
    existing = cursor.fetchall()
    phones = {row[0] for row in existing}
    emails = {row[1] for row in existing}
    pans = {row[2] for row in existing}

    customers = []
    profiles = {}
    genders = ["Male", "Female"] * 50
    kyc_states = ["Approved"] * 75 + ["Pending"] * 15 + ["Rejected"] * 10
    rng.shuffle(genders)
    rng.shuffle(kyc_states)
    for offset in range(100):
        customer_id = first_customer + offset
        gender = genders[offset]
        first_name = fake.first_name_male() if gender == "Male" else fake.first_name_female()
        last_name = fake.last_name()
        branch_id, pincode, ifsc = rng.choice(branches)
        city, state = postal[pincode]
        address = f"{fake.building_number()}, {fake.street_name()}, {city}, {state} {pincode}"
        phone = unique_value(lambda: fake.numerify(f"{rng.choice('6789')}#########"), phones)
        # Five uppercase letters, four digits, final uppercase letter; P marks
        # an individual PAN. All values are fictional, not identity verification.
        pan = unique_value(lambda: fake.bothify("???P?####?").upper(), pans)
        name_slug = re.sub(r"[^a-z0-9]", "", f"{first_name}{last_name}".lower())[:50] or "customer"
        email = unique_value(
            lambda: f"{name_slug}.{customer_id}.{fake.numerify('####')}@example.com", emails
        )
        age = rng.randint(21, 75)
        kyc = kyc_states[offset]
        customers.append((customer_id, first_name[:50], last_name[:50], gender, age,
                          address[:200], phone, email, pan, kyc))
        profiles[customer_id] = {"branch": branch_id, "age": age, "kyc": kyc}

    insert_rows(cursor, "Customer", (
        "CustomerID", "FirstName", "LastName", "Gender", "Age", "Address", "Phone", "Email", "PAN_Number", "KYC_Status"
    ), customers, "CustomerID")

    accounts = []
    account_details = {}
    customer_ids = list(profiles)
    # Every new customer gets one Savings account. Fifty receive a second
    # product, ensuring the passbook and multi-account queries have rich data.
    owners = customer_ids + rng.sample(customer_ids, 50)
    for offset, customer_id in enumerate(owners):
        account_no = first_account + offset
        profile = profiles[customer_id]
        primary = offset < 100
        account_type = "Savings" if primary else rng.choice(["Savings", "Current", "Salary"])
        branch_id = profile["branch"] if primary else rng.choice(branches)[0]
        balance = Decimal(rng.randint(100_000, 50_000_000)) / 100
        rate = Decimal("0.00") if account_type == "Current" else rng.choice([
            Decimal("3.50"), Decimal("3.75"), Decimal("4.00")
        ])
        opening = today - timedelta(days=rng.randint(90, min(1825, (profile["age"] - 18) * 365)))
        status = "Active" if profile["kyc"] == "Approved" else "Frozen"
        if not primary and status == "Active":
            status = rng.choices(["Active", "Dormant", "Frozen"], weights=[85, 10, 5])[0]
        accounts.append((account_no, customer_id, branch_id, account_type, balance, rate, opening, status))
        account_details[account_no] = {"opening": opening, "owner": customer_id}
        if primary:
            profile["opening"] = opening

    insert_rows(cursor, "Account", (
        "AccountNo", "CustomerID", "BranchID", "AccountType", "Balance", "InterestRate", "OpeningDate", "Status"
    ), accounts, "AccountNo")

    # Use distinct approved borrowers and leave other customers loan-free.
    eligible = [customer_id for customer_id in customer_ids if profiles[customer_id]["kyc"] == "Approved"]
    borrowers = rng.sample(eligible, 50)
    loans = []
    loan_types = ["Auto", "Home", "Personal"] * 17
    rng.shuffle(loan_types)
    for offset, customer_id in enumerate(borrowers):
        loan_type = loan_types[offset]
        if loan_type == "Home":
            principal = Decimal(rng.randint(1000, 9000) * 1000)
            rate = Decimal(rng.randint(800, 1050)) / 100
            months = rng.choice([120, 180, 240, 300])
        elif loan_type == "Auto":
            principal = Decimal(rng.randint(300, 1500) * 1000)
            rate = Decimal(rng.randint(850, 1200)) / 100
            months = rng.choice([36, 48, 60, 84])
        else:
            principal = Decimal(rng.randint(50, 750) * 1000)
            rate = Decimal(rng.randint(1050, 1600)) / 100
            months = rng.choice([12, 24, 36, 48, 60])
        opening = profiles[customer_id]["opening"]
        issue = opening + timedelta(days=rng.randint(0, (today - opening).days))
        installments = rng.randint(0, min(months - 1, (today - issue).days // 31))
        monthly_rate = rate / 1200
        factor = (1 + monthly_rate) ** months
        unrounded_emi = principal * monthly_rate * factor / (factor - 1)
        elapsed_factor = (1 + monthly_rate) ** installments
        outstanding = money(principal * elapsed_factor - unrounded_emi * (elapsed_factor - 1) / monthly_rate)
        status = rng.choices(["Active", "Defaulted"], weights=[90, 10])[0]
        loans.append((first_loan + offset, customer_id, profiles[customer_id]["branch"], loan_type,
                      principal, rate, months, outstanding, issue, status))

    # Omit EMI_Amount: PostgreSQL generates it from the supplied loan terms.
    insert_rows(cursor, "Loan", (
        "LoanID", "CustomerID", "BranchID", "LoanType", "PrincipalAmount", "InterestRate",
        "TenureMonths", "OutstandingBalance", "IssueDate", "Status"
    ), loans, "LoanID")

    transactions = []
    account_numbers = list(account_details)
    # At least three events per account (450), plus fifty additional events.
    event_accounts = account_numbers * 3 + rng.choices(account_numbers, k=50)
    rng.shuffle(event_accounts)
    narratives = {
        "Deposit": ["Salary credit", "Business receipts", "Savings contribution", "Family remittance"],
        "Withdrawal": ["Grocery payment", "Utility bill", "Education fees", "Rent payment"],
        "Transfer": ["Debit: family transfer", "Credit: incoming transfer", "Debit: supplier settlement"],
    }
    bank_names = list(banks.values())
    for offset, account_no in enumerate(event_accounts):
        transaction_type = rng.choice(["Deposit", "Withdrawal", "Transfer"])
        mode = rng.choice(["UPI", "NEFT", "IMPS"])
        amount = Decimal(rng.randint(10_000, 10_000_000)) / 100
        earliest = datetime.combine(account_details[account_no]["opening"], time.min)
        date = earliest + timedelta(seconds=rng.randint(0, max(0, int((now - earliest).total_seconds()) - 1)))
        remarks = None if offset % 10 == 0 else f"{rng.choice(narratives[transaction_type])} via {rng.choice(bank_names)}"
        transactions.append((account_no, amount, transaction_type, mode, remarks, date))

    insert_rows(cursor, "Transaction_History", (
        "AccountNo", "Amount", "TransactionType", "PaymentMode", "Remarks", "TransactionDate"
    ), transactions, "TransactionID")

    # Twenty-five FD holders also borrow; fifteen have no loan, creating real
    # cross-sell candidates for CQ-03. All have an Active primary Savings account.
    nonborrowers = [customer_id for customer_id in eligible if customer_id not in borrowers]
    fd_owners = rng.sample(borrowers, 25) + rng.sample(nonborrowers, 15)
    rng.shuffle(fd_owners)
    deposits = []
    for offset, customer_id in enumerate(fd_owners):
        opening = profiles[customer_id]["opening"]
        start = opening + timedelta(days=rng.randint(0, (today - opening).days))
        # Future maturity dates provide current Active FD holdings for the UI.
        end = today + timedelta(days=rng.choice([30, 90, 180, 365, 730]))
        amount = Decimal(rng.randint(5, 1000) * 1000)
        rate = Decimal(rng.randint(600, 800)) / 100
        deposits.append((first_fd + offset, customer_id, amount, rate, start, end, "Active"))

    # Omit MaturityAmount: PostgreSQL calculates actual-day simple interest.
    insert_rows(cursor, "Fixed_Deposit", (
        "FD_ID", "CustomerID", "Amount", "InterestRate", "StartDate", "EndDate", "Status"
    ), deposits, "FD_ID")

    after = table_counts(cursor)
    for table, expected in EXPECTED.items():
        if after[table] - before[table] != expected:
            raise RuntimeError(f"{table}: row-count verification failed; rolling back")
    ranges = {
        "CustomerID": (first_customer, first_customer + 99),
        "AccountNo": (first_account, first_account + 149),
        "LoanID": (first_loan, first_loan + 49),
        "FD_ID": (first_fd, first_fd + 39),
    }
    return before, after, ranges


def main() -> int:
    connection = None
    try:
        connection = psycopg2.connect(
            dbname="banking_db", user="postgres", password="admin", host="localhost", port=5432,
            connect_timeout=5, application_name="banking_bulk_seed",
        )
        connection.autocommit = False
        with connection.cursor() as cursor:
            before, after, ranges = seed_data(cursor)
        # Exactly one commit; any earlier failure rolls back every batch.
        connection.commit()
    except Exception as e:
        if connection is not None:
            connection.rollback()
        print(f"Bulk seed FAILED: {e}. Transaction rolled back; no seed rows committed.", file=sys.stderr)
        return 1
    finally:
        if connection is not None:
            connection.close()

    print("SUCCESS: bulk data committed and all five row-count increments verified.")
    print(f"{'Table':<24} {'Inserted':>10} {'Total rows':>12}")
    for table in EXPECTED:
        print(f"{table:<24} {after[table] - before[table]:>10} {after[table]:>12}")
    for label, (first, last) in ranges.items():
        print(f"New {label}: {first} through {last}")
    print("Refresh the Streamlit dashboard to see the new data.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
