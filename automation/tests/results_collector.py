"""Process-wide accumulator for scenario results.

conftest.py flushes this to automation/reports/JSON/results_<suite>_<shard>.json in
pytest_sessionfinish. It lives in its own module so every suite writes into the same list
regardless of collection order.
"""

RESULTS = []


def record(result: dict) -> dict:
    """Stores a scenario result for end-of-session reporting and returns it unchanged."""
    RESULTS.append(result)
    return result


def clear() -> None:
    RESULTS.clear()
