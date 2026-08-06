import os
import pytest
from selenium import webdriver
from automation.utils.driver_factory import DriverFactory
from automation.utils.screenshot_util import take_screenshot
from automation.utils.logger_util import logger
from automation.config.config import Config

@pytest.fixture(scope="function")
def driver(request):
    """Fixture to instantiate and manage Chrome webdriver lifecycle."""
    driver = DriverFactory.get_chrome_driver()
    
    yield driver
    
    # Take failure screenshot if test failed
    if hasattr(request.node, "rep_call") and request.node.rep_call.failed:
        test_name = request.node.name
        logger.error(f"Test '{test_name}' failed. Capturing diagnostic screenshot.")
        take_screenshot(driver, f"failure_{test_name}")
        
    try:
        driver.quit()
        logger.debug("Driver shutdown successfully.")
    except Exception as e:
        logger.warning(f"Error quitting driver: {str(e)}")

@pytest.hookimpl(tryfirst=True, hookwrapper=True)
def pytest_runtest_makereport(item, call):
    """Hook to capture test execution outcomes for the driver fixture."""
    outcome = yield
    rep = outcome.get_result()
    setattr(item, "rep_" + rep.when, rep)
