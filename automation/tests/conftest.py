import os

import pytest

from automation.config.config import Config
from automation.tests import results_collector
from automation.utils.logger_util import logger


@pytest.fixture(scope="session")
def driver():
    """One Chrome instance per pytest session.

    Session scope is deliberate: the functional suite runs hundreds of scenarios, and a
    function-scoped driver would start and quit a browser for every one of them (roughly an
    hour of pure startup cost per shard). Each scenario re-navigates to the base URL, so it
    still begins from a known state.
    """
    # Imported lazily so the load/vulnerability suites, which never request this fixture,
    # do not need Selenium installed.
    from automation.utils.driver_factory import DriverFactory

    instance = DriverFactory.get_chrome_driver()
    yield instance

    try:
        instance.quit()
        logger.debug("Driver shutdown successfully.")
    except Exception as exc:
        logger.warning(f"Error quitting driver: {exc}")


@pytest.fixture(scope="session")
def appium_driver():
    """One Appium session for the whole native suite.

    Skips cleanly when no Appium server or device is reachable, which is the case on CI
    runners — there the suite is collected to prove it is valid, and executed locally.
    """
    from automation.appium.driver_factory import appium_server_available, create_driver

    if not appium_server_available():
        pytest.skip("No Appium server or device available.")

    instance = create_driver()
    yield instance

    try:
        instance.quit()
        logger.debug("Appium session closed.")
    except Exception as exc:
        logger.warning(f"Error closing Appium session: {exc}")


@pytest.hookimpl(tryfirst=True, hookwrapper=True)
def pytest_runtest_makereport(item, call):
    """Exposes each phase's report on the item for downstream inspection."""
    outcome = yield
    report = outcome.get_result()
    setattr(item, "rep_" + report.when, report)


def pytest_sessionfinish(session, exitstatus):
    """Writes this suite/shard's results for the aggregation job to collect.

    This hook must live in conftest.py — pytest only honours pytest_sessionfinish in conftest
    files and plugins, so the previous definition inside test_selenium.py never ran and no
    intermediate JSON was ever produced.
    """
    from automation.utils.report_generator import ReportGenerator

    os.makedirs(Config.JSON_DIR, exist_ok=True)
    results = list(results_collector.RESULTS)
    ReportGenerator.save_intermediate_results(Config.result_file_name(), results)
    logger.info(
        f"Pytest session finished. Wrote {len(results)} results for "
        f"suite={Config.SUITE} shard={Config.SHARD_INDEX}/{Config.SHARD_TOTAL}."
    )
