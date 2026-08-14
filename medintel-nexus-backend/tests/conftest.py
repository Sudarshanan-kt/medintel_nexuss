"""Keeps the suite off the developer's own records database.

`app/records_db.py` defaults to `data/records.sqlite3`, which is where real
scans land. Tests create, fail and verify prescriptions freely, so they get a
throwaway file for the session instead — otherwise a test run would leave its
fixtures sitting in the history the app shows.
"""

import pytest

from app import records_db


@pytest.fixture(autouse=True, scope="session")
def records_db_in_tmp(tmp_path_factory: pytest.TempPathFactory):
    original = records_db.db_path()
    records_db.use(tmp_path_factory.mktemp("records") / "records.sqlite3")
    yield
    records_db.use(original)
