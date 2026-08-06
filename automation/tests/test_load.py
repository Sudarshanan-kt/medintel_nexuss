"""Load / performance suite — 300 scenarios driven against the FastAPI backend.

No browser is involved, so the CI job for this suite skips Chrome setup entirely.
"""

import pytest

from automation.tests.results_collector import record
from automation.utils.scenario_runner import execute_scenario, select_scenarios

SCENARIOS = select_scenarios("performance")


@pytest.mark.performance
@pytest.mark.parametrize("scenario", SCENARIOS, ids=lambda s: s["id"])
def test_performance_scenario(scenario):
    result = record(execute_scenario(scenario))
    if result["status"] == "Failed":
        pytest.fail(result["error_message"])
