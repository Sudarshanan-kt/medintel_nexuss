"""Unit / state-management suite running 300 programmatic scenarios.
"""

import pytest

from automation.tests.results_collector import record
from automation.utils.scenario_runner import execute_scenario, select_scenarios

SCENARIOS = select_scenarios("unit")


@pytest.mark.unit
@pytest.mark.parametrize("scenario", SCENARIOS, ids=lambda s: s["id"])
def test_unit_scenario(scenario):
    result = record(execute_scenario(scenario))
    if result["status"] == "Failed":
        pytest.fail(result["error_message"])
