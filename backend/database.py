"""Short-lived database connections compatible with committing procedures."""

from contextlib import contextmanager
import os

import psycopg2
from psycopg2.extras import RealDictCursor


DATABASE_URL = os.getenv(
    "DATABASE_URL", "postgresql://postgres:admin@localhost:5432/banking_db"
)


@contextmanager
def get_connection(autocommit: bool = True):
    connection = None
    try:
        connection = psycopg2.connect(
            DATABASE_URL,
            connect_timeout=5,
            application_name="core_banking_api",
            options="-c search_path=pg_catalog,public -c statement_timeout=15000 -c lock_timeout=5000",
        )
        # A connection context (with connection:) would start an enclosing
        # transaction and break sp_transfer_funds's explicit COMMIT. Each CALL
        # runs independently; a failed statement is rolled back by PostgreSQL.
        connection.autocommit = autocommit
        yield connection
        if not autocommit:
            connection.commit()
    except Exception:
        if connection is not None and not connection.closed:
            connection.rollback()
        raise
    finally:
        if connection is not None and not connection.closed:
            connection.close()


def fetch_all(query: str, params: tuple = ()) -> list[dict]:
    with get_connection() as connection:
        with connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(query, params)
            return [dict(row) for row in cursor.fetchall()]


def fetch_one(query: str, params: tuple = ()) -> dict | None:
    with get_connection() as connection:
        with connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(query, params)
            row = cursor.fetchone()
            return dict(row) if row is not None else None


def execute(query: str, params: tuple = ()) -> None:
    with get_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(query, params)


@contextmanager
def transaction():
    """A single atomic multi-statement transaction; all failures roll it back."""
    with get_connection(autocommit=False) as connection:
        with connection.cursor(cursor_factory=RealDictCursor) as cursor:
            yield cursor
