"""Functional (Selenium) suite — 900 scenarios driven against the deployed web build.

Sharded across runners via SHARD_INDEX/SHARD_TOTAL. The browser is session-scoped (see
conftest.py), so a shard reuses one Chrome instance instead of launching one per scenario.
"""

import pytest

from automation.tests.results_collector import record
from automation.utils.scenario_runner import execute_scenario, select_scenarios

SCENARIOS = select_scenarios("functional")


@pytest.mark.functional
@pytest.mark.parametrize("scenario", SCENARIOS, ids=lambda s: s["id"])
def test_functional_scenario(driver, scenario):
    result = record(execute_scenario(scenario, driver=driver))
    if result["status"] == "Failed":
        pytest.fail(result["error_message"])
