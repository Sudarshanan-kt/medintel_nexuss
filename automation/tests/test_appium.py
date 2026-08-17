"""Native Android (Appium) suite running 300 programmatic scenarios.
"""

import pytest

from automation.tests.results_collector import record
from automation.utils.scenario_runner import execute_scenario, select_scenarios

SCENARIOS = select_scenarios("appium")


@pytest.mark.appium
@pytest.mark.parametrize("scenario", SCENARIOS, ids=lambda s: s["id"])
def test_appium_scenario(scenario):
    record(execute_scenario(scenario))
