"""Screen objects for the native Android app.

Mirrors the structure of automation/pages/ (the Selenium page objects) so both layers read the
same way. Flutter draws to a single canvas, so elements are located by accessibility label —
these correspond to Semantics labels in the Flutter widget tree.
"""

from automation.utils.logger_util import logger


class BaseScreen:
    def __init__(self, driver):
        self.driver = driver

    def _by_accessibility_id(self, identifier):
        from appium.webdriver.common.appiumby import AppiumBy

        return self.driver.find_element(AppiumBy.ACCESSIBILITY_ID, identifier)

    def _all_by_accessibility_id(self, identifier):
        from appium.webdriver.common.appiumby import AppiumBy

        return self.driver.find_elements(AppiumBy.ACCESSIBILITY_ID, identifier)

    def is_displayed(self, identifier) -> bool:
        return len(self._all_by_accessibility_id(identifier)) > 0


class LoginScreen(BaseScreen):
    EMAIL_FIELD = "login_email_field"
    PASSWORD_FIELD = "login_password_field"
    SUBMIT_BUTTON = "login_submit_button"

    def login(self, email: str, password: str):
        logger.info(f"Signing in as {email} on the native app.")
        self._by_accessibility_id(self.EMAIL_FIELD).send_keys(email)
        self._by_accessibility_id(self.PASSWORD_FIELD).send_keys(password)
        self._by_accessibility_id(self.SUBMIT_BUTTON).click()


class DashboardScreen(BaseScreen):
    ROOT = "dashboard_root"
    SOS_BUTTON = "dashboard_sos_button"
    REMINDERS_TILE = "dashboard_reminders_tile"
    REPORTS_TILE = "dashboard_reports_tile"

    def open_reminders(self):
        self._by_accessibility_id(self.REMINDERS_TILE).click()

    def open_reports(self):
        self._by_accessibility_id(self.REPORTS_TILE).click()


class PrescriptionScanScreen(BaseScreen):
    ROOT = "prescription_scan_root"
    CAPTURE_BUTTON = "prescription_capture_button"
    RESULT_LIST = "prescription_result_list"
