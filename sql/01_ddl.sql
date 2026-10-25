-- Sprint 1. Destructive reset of the twelve project tables and dependants.
-- Unquoted identifiers follow PostgreSQL's normal lowercase folding.
BEGIN;

DROP TABLE IF EXISTS Audit_Log CASCADE;
DROP TABLE IF EXISTS Employee CASCADE;
DROP TABLE IF EXISTS Fixed_Deposit CASCADE;
DROP TABLE IF EXISTS Beneficiary CASCADE;
DROP TABLE IF EXISTS Loan_Repayment CASCADE;
DROP TABLE IF EXISTS Loan CASCADE;
DROP TABLE IF EXISTS Transaction_History CASCADE;
DROP TABLE IF EXISTS Account CASCADE;
DROP TABLE IF EXISTS Customer CASCADE;
DROP TABLE IF EXISTS Branch CASCADE;
DROP TABLE IF EXISTS Bank_Directory CASCADE;
DROP TABLE IF EXISTS Postal_Directory CASCADE;

CREATE TABLE Postal_Directory (
    Pincode VARCHAR(10) PRIMARY KEY,
    City VARCHAR(50) NOT NULL,
    State VARCHAR(50) NOT NULL
);

CREATE TABLE Bank_Directory (
    IFSC_Code VARCHAR(15) PRIMARY KEY,
    BankName VARCHAR(100) NOT NULL
);

CREATE TABLE Branch (
    BranchID INT PRIMARY KEY,
    BranchName VARCHAR(100) NOT NULL,
    Address VARCHAR(200) NOT NULL,
    Pincode VARCHAR(10) NOT NULL REFERENCES Postal_Directory(Pincode),
    IFSC_Code VARCHAR(15) UNIQUE NOT NULL,
    ContactPhone VARCHAR(15) UNIQUE NOT NULL
);

CREATE TABLE Customer (
    CustomerID INT PRIMARY KEY,
    FirstName VARCHAR(50) NOT NULL,
    LastName VARCHAR(50) NOT NULL,
    Gender VARCHAR(10) NOT NULL CHECK (Gender IN ('Male', 'Female', 'Other')),
    Age INT NOT NULL CHECK (Age >= 18),
    Address VARCHAR(200) NOT NULL,
    Phone VARCHAR(15) UNIQUE NOT NULL,
    Email VARCHAR(100) UNIQUE NOT NULL,
    PAN_Number VARCHAR(10) UNIQUE NOT NULL,
    KYC_Status VARCHAR(20) DEFAULT 'Pending'
        CHECK (KYC_Status IN ('Pending', 'Approved', 'Rejected'))
);

CREATE TABLE Account (
    AccountNo INT PRIMARY KEY,
    CustomerID INT NOT NULL REFERENCES Customer(CustomerID) ON DELETE CASCADE,
    BranchID INT NOT NULL REFERENCES Branch(BranchID),
    AccountType VARCHAR(20) NOT NULL CHECK (AccountType IN ('Savings', 'Current', 'Salary')),
    Balance DECIMAL(15, 2) NOT NULL CHECK (Balance >= 0),
    InterestRate DECIMAL(5, 2) DEFAULT 3.50 NOT NULL,
    OpeningDate DATE DEFAULT CURRENT_DATE NOT NULL,
    Status VARCHAR(15) DEFAULT 'Active'
        CHECK (Status IN ('Active', 'Dormant', 'Frozen', 'Closed'))
);

CREATE TABLE Transaction_History (
    TransactionID SERIAL PRIMARY KEY,
    AccountNo INT NOT NULL REFERENCES Account(AccountNo),
    Amount DECIMAL(15, 2) NOT NULL CHECK (Amount > 0),
    TransactionType VARCHAR(20) NOT NULL CHECK (TransactionType IN ('Deposit', 'Withdrawal', 'Transfer')),
    PaymentMode VARCHAR(20) NOT NULL CHECK (PaymentMode IN ('UPI', 'NEFT', 'RTGS', 'IMPS', 'Cash', 'Internal')),
    Remarks VARCHAR(255) NULL,
    TransactionDate TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Loan (
    LoanID INT PRIMARY KEY,
    CustomerID INT NOT NULL REFERENCES Customer(CustomerID),
    BranchID INT NOT NULL REFERENCES Branch(BranchID),
    LoanType VARCHAR(30) NOT NULL CHECK (LoanType IN ('Home', 'Personal', 'Auto', 'Education', 'Business')),
    PrincipalAmount DECIMAL(15, 2) NOT NULL CHECK (PrincipalAmount > 0),
    InterestRate DECIMAL(5, 2) NOT NULL CHECK (InterestRate > 0),
    TenureMonths INT NOT NULL CHECK (TenureMonths > 0),
    EMI_Amount DECIMAL(15, 2) GENERATED ALWAYS AS (
        ROUND((PrincipalAmount * (InterestRate / 1200.0)
            * POWER(1 + (InterestRate / 1200.0), TenureMonths))
            / (POWER(1 + (InterestRate / 1200.0), TenureMonths) - 1), 2)
    ) STORED,
    OutstandingBalance DECIMAL(15, 2) NOT NULL CHECK (OutstandingBalance >= 0),
    IssueDate DATE DEFAULT CURRENT_DATE NOT NULL,
    Status VARCHAR(20) DEFAULT 'Approved'
        CHECK (Status IN ('Pending', 'Approved', 'Active', 'Closed', 'Defaulted'))
);

CREATE TABLE Loan_Repayment (
    PaymentID SERIAL PRIMARY KEY,
    LoanID INT NOT NULL REFERENCES Loan(LoanID) ON DELETE CASCADE,
    AmountPaid DECIMAL(15, 2) NOT NULL CHECK (AmountPaid > 0),
    PaymentMode VARCHAR(20) NOT NULL CHECK (PaymentMode IN ('Auto-Debit', 'UPI', 'NEFT', 'Cash')),
    PaymentStatus VARCHAR(20) DEFAULT 'Success'
        CHECK (PaymentStatus IN ('Success', 'Pending', 'Failed')),
    PaymentDate TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Beneficiary (
    BeneficiaryID SERIAL PRIMARY KEY,
    CustomerID INT NOT NULL REFERENCES Customer(CustomerID) ON DELETE CASCADE,
    BeneficiaryName VARCHAR(100) NOT NULL,
    LinkedAccountNo BIGINT NOT NULL,
    IFSC_Code VARCHAR(15) NOT NULL REFERENCES Bank_Directory(IFSC_Code),
    MaxTransferLimit DECIMAL(15, 2) DEFAULT 100000.00 NOT NULL
);

CREATE TABLE Fixed_Deposit (
    FD_ID INT PRIMARY KEY,
    CustomerID INT NOT NULL REFERENCES Customer(CustomerID),
    Amount DECIMAL(15, 2) NOT NULL CHECK (Amount >= 1000),
    InterestRate DECIMAL(5, 2) NOT NULL,
    StartDate DATE DEFAULT CURRENT_DATE NOT NULL,
    EndDate DATE NOT NULL,
    MaturityAmount DECIMAL(15, 2) GENERATED ALWAYS AS (
        ROUND(Amount + (Amount * InterestRate * (EndDate - StartDate) / 36500.0), 2)
    ) STORED,
    Status VARCHAR(20) DEFAULT 'Active' CHECK (Status IN ('Active', 'Matured', 'Closed')),
    CHECK (EndDate > StartDate)
);

CREATE TABLE Employee (
    EmployeeID INT PRIMARY KEY,
    BranchID INT NOT NULL REFERENCES Branch(BranchID),
    FirstName VARCHAR(50) NOT NULL,
    LastName VARCHAR(50) NOT NULL,
    Email VARCHAR(100) UNIQUE NOT NULL,
    Role VARCHAR(30) NOT NULL,
    Salary DECIMAL(12, 2) NOT NULL CHECK (Salary > 0),
    HireDate DATE DEFAULT CURRENT_DATE NOT NULL
);

CREATE TABLE Audit_Log (
    LogID SERIAL PRIMARY KEY,
    TableName VARCHAR(50) NOT NULL,
    RecordID INT NOT NULL,
    ActionType VARCHAR(50) NOT NULL,
    Description TEXT NOT NULL,
    LogDate TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMIT;
