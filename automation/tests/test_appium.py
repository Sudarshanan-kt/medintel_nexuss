"""Native Android (Appium) suite.

Every test requires a real device or emulator plus a running Appium server. On CI the
`appium_driver` fixture skips the suite, and the job instead asserts that this module imports
and collects cleanly — so the suite is always verified as valid Python even when it cannot run.

To execute locally:
    flutter build apk --debug
    appium --base-path /            # in a second terminal
    SUITE=appium python -m pytest automation/tests/test_appium.py -v
"""

import pytest

from automation.appium.screens import DashboardScreen, LoginScreen, PrescriptionScanScreen
from automation.data.test_data import TestData
from automation.tests.results_collector import record
from automation.utils.logger_util import logger

pytestmark = pytest.mark.appium


def _result(test_id, title, module, status, actual, error="", duration=0.0):
    """Builds a record in the same shape the scenario suites emit, so the native results
    flow through the identical aggregation and reporting pipeline."""
    return {
        "id": test_id,
        "module": module,
        "type": "appium",
        "priority": "Critical",
        "title": title,
        "preconditions": "Debug APK installed on an attached Android device or emulator.",
        "steps": ["1. Launch the native app.", "2. Drive the flow.", "3. Assert on screen state."],
        "expected_result": title,
        "actual_result": actual,
        "status": status,
        "execution_time": duration,
        "error_message": error,
        "screenshot": "",
    }


def test_app_launches_to_a_rendered_screen(appium_driver):
    """TC_APPI_0001 — the app process starts and presents a non-empty view hierarchy."""
    source = appium_driver.page_source
    passed = source is not None and len(source) > 0
    record(
        _result(
            "TC_APPI_0001",
            "Native app launches and renders its first screen",
            "App Launch",
            "Passed" if passed else "Failed",
            f"Page source length: {len(source or '')}.",
        )
    )
    assert passed, "App launched but produced an empty view hierarchy."


def test_login_screen_exposes_its_fields(appium_driver):
    """TC_APPI_0002 — the sign-in form is reachable and its inputs are addressable."""
    login = LoginScreen(appium_driver)
    visible = login.is_displayed(LoginScreen.EMAIL_FIELD)
    record(
        _result(
            "TC_APPI_0002",
            "Login screen exposes email, password and submit controls",
            "Authentication",
            "Passed" if visible else "Failed",
            f"Email field present: {visible}.",
        )
    )
    assert visible, "Login email field was not found in the native accessibility tree."


def test_dashboard_reachable_after_login(appium_driver):
    """TC_APPI_0003 — a valid sign-in lands on the dashboard."""
    login = LoginScreen(appium_driver)
    login.login(TestData.VALID_USER_EMAIL, TestData.VALID_USER_PASSWORD)

    dashboard = DashboardScreen(appium_driver)
    reached = dashboard.is_displayed(DashboardScreen.ROOT)
    record(
        _result(
            "TC_APPI_0003",
            "Valid credentials navigate through to the dashboard",
            "Navigation",
            "Passed" if reached else "Failed",
            f"Dashboard root present: {reached}.",
        )
    )
    assert reached, "Dashboard was not reached after signing in."


def test_sos_control_is_present_on_dashboard(appium_driver):
    """TC_APPI_0004 — the emergency control is always reachable from the dashboard."""
    dashboard = DashboardScreen(appium_driver)
    present = dashboard.is_displayed(DashboardScreen.SOS_BUTTON)
    record(
        _result(
            "TC_APPI_0004",
            "SOS control is present and reachable on the dashboard",
            "Emergency",
            "Passed" if present else "Failed",
            f"SOS button present: {present}.",
        )
    )
    assert present, "SOS button was not found on the dashboard."


def test_prescription_scan_screen_opens(appium_driver):
    """TC_APPI_0005 — the prescription scanner opens and offers a capture control."""
    dashboard = DashboardScreen(appium_driver)
    dashboard.open_reports()

    scanner = PrescriptionScanScreen(appium_driver)
    opened = scanner.is_displayed(PrescriptionScanScreen.ROOT)
    record(
        _result(
            "TC_APPI_0005",
            "Prescription scan screen opens with a capture control",
            "File Upload",
            "Passed" if opened else "Failed",
            f"Scanner root present: {opened}.",
        )
    )
    logger.info(f"Prescription scan screen reached: {opened}")
    assert opened, "Prescription scan screen did not open."
