"""Validated REST inputs mapped to the unchanged twelve-table banking schema."""
from datetime import date
from decimal import Decimal
from typing import Annotated, Literal
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

DatabaseID = Annotated[int, Field(ge=1, le=2_147_483_647)]
Money = Annotated[Decimal, Field(gt=0, max_digits=15, decimal_places=2, allow_inf_nan=False)]
Balance = Annotated[Decimal, Field(ge=0, max_digits=15, decimal_places=2, allow_inf_nan=False)]
Rate = Annotated[Decimal, Field(ge=0, le=999, max_digits=5, decimal_places=2, allow_inf_nan=False)]
PaymentMode = Literal['UPI', 'NEFT', 'RTGS', 'IMPS', 'Cash', 'Internal']
AccountStatus = Literal['Active', 'Dormant', 'Frozen', 'Closed']
KYCStatus = Literal['Pending', 'Approved', 'Rejected']

class RequestModel(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)

class LoginRequest(RequestModel):
    id: DatabaseID
    role: Literal['Admin', 'Customer']
    identity_type: Literal['customer', 'account'] = 'customer'
    employee_id: DatabaseID | None = None

    @field_validator('role', mode='before')
    @classmethod
    def normalize_role(cls, value):
        return value.strip().title() if isinstance(value, str) else value

class TransferRequest(RequestModel):
    customer_id: DatabaseID | None = None
    sender: DatabaseID
    receiver: DatabaseID | None = None
    beneficiary_id: DatabaseID | None = None
    amount: Money
    mode: PaymentMode
    remarks: str | None = Field(default=None, max_length=180)

    @model_validator(mode='after')
    def destination(self):
        if (self.receiver is None) == (self.beneficiary_id is None):
            raise ValueError('Choose exactly one receiver account or saved beneficiary')
        if self.beneficiary_id is not None and self.customer_id is None:
            raise ValueError('customer_id is required for beneficiary transfers')
        return self

class CashRequest(RequestModel):
    customer_id: DatabaseID
    account_no: DatabaseID
    amount: Money
    mode: PaymentMode = 'Cash'
    remarks: str | None = Field(default=None, max_length=200)

class EMIRequest(RequestModel):
    customer_id: DatabaseID
    loan_id: DatabaseID
    account_no: DatabaseID

class BeneficiaryRequest(RequestModel):
    beneficiary_name: str = Field(min_length=1, max_length=100)
    linked_account_no: Annotated[int, Field(ge=1, le=9_223_372_036_854_775_807)]
    ifsc_code: str = Field(min_length=1, max_length=15, pattern=r'^[A-Z0-9]+$')
    bank_name: str | None = Field(default=None, min_length=1, max_length=100)
    max_transfer_limit: Money = Decimal('100000.00')

class FDRequest(RequestModel):
    account_no: DatabaseID | None = None
    amount: Annotated[Decimal, Field(ge=1000, max_digits=15, decimal_places=2, allow_inf_nan=False)]
    interest_rate: Rate
    start_date: date | None = None
    end_date: date

class CustomerCreate(RequestModel):
    first_name: str = Field(min_length=1, max_length=50)
    last_name: str = Field(min_length=1, max_length=50)
    gender: Literal['Male', 'Female', 'Other']
    age: int = Field(ge=18, le=120)
    address: str = Field(min_length=1, max_length=200)
    phone: str = Field(min_length=1, max_length=15)
    email: str = Field(min_length=3, max_length=100)
    pan_number: str = Field(pattern=r'^[A-Z]{5}[0-9]{4}[A-Z]$')
    kyc_status: KYCStatus = 'Pending'

class KYCUpdate(RequestModel):
    kyc_status: KYCStatus

class AccountCreate(RequestModel):
    customer_id: DatabaseID
    branch_id: DatabaseID
    account_type: Literal['Savings', 'Current', 'Salary']
    balance: Balance = Decimal('0.00')
    interest_rate: Rate = Decimal('3.50')

class AccountStatusUpdate(RequestModel):
    status: AccountStatus

class LoanCreate(RequestModel):
    customer_id: DatabaseID
    branch_id: DatabaseID
    loan_type: Literal['Home', 'Personal', 'Auto', 'Education', 'Business']
    principal_amount: Money
    interest_rate: Annotated[Decimal, Field(gt=0, le=999, max_digits=5, decimal_places=2)]
    tenure_months: int = Field(ge=1, le=600)
    account_no: DatabaseID | None = None

class PostalCreate(RequestModel):
    pincode: str = Field(min_length=1, max_length=10)
    city: str = Field(min_length=1, max_length=50)
    state: str = Field(min_length=1, max_length=50)

class BankCreate(RequestModel):
    ifsc_code: str = Field(min_length=1, max_length=15, pattern=r'^[A-Z0-9]+$')
    bank_name: str = Field(min_length=1, max_length=100)

class BranchCreate(PostalCreate, BankCreate):
    branch_name: str = Field(min_length=1, max_length=100)
    address: str = Field(min_length=1, max_length=200)
    contact_phone: str = Field(min_length=1, max_length=15)

class EmployeeCreate(RequestModel):
    branch_id: DatabaseID
    first_name: str = Field(min_length=1, max_length=50)
    last_name: str = Field(min_length=1, max_length=50)
    email: str = Field(min_length=3, max_length=100)
    role: str = Field(min_length=1, max_length=30)
    salary: Annotated[Decimal, Field(gt=0, max_digits=12, decimal_places=2)]
    hire_date: date | None = None
