from selenium.webdriver.common.by import By
from automation.pages.base_page import BasePage
from automation.utils.logger_util import logger

class DashboardPage(BasePage):
    # Selectors for main page elements
    NAV_DRAWER = (By.XPATH, "//button[@aria-label='Open navigation menu'] or //*[contains(@class, 'menu')]")
    SCANNER_TAB = (By.XPATH, "//*[contains(text(), 'Scan') or contains(@aria-label, 'Scan')]")
    REPORTS_TAB = (By.XPATH, "//*[contains(text(), 'Reports') or contains(@aria-label, 'Reports')]")
    VITALS_TAB = (By.XPATH, "//*[contains(text(), 'Vitals') or contains(@aria-label, 'Vitals')]")
    SOS_BUTTON = (By.XPATH, "//*[contains(text(), 'SOS') or contains(@aria-label, 'SOS')]")
    PROFILE_ICON = (By.XPATH, "//*[contains(@aria-label, 'Profile') or contains(@class, 'avatar')]")
    
    def open_menu(self):
        logger.info("Opening dashboard navigation menu.")
        self.click_element(self.NAV_DRAWER)

    def go_to_scanner(self):
        logger.info("Navigating to prescription scanner.")
        self.click_element(self.SCANNER_TAB)

    def go_to_reports(self):
        logger.info("Navigating to reports section.")
        self.click_element(self.REPORTS_TAB)

    def trigger_sos(self):
        logger.info("Triggering SOS countdown.")
        self.click_element(self.SOS_BUTTON)

    def go_to_profile(self):
        logger.info("Navigating to profile sheet.")
        self.click_element(self.PROFILE_ICON)
        
    def is_dashboard_loaded(self) -> bool:
        self.wait_for_flutter_load()
        # Verify dashboard indicators or SOS button are present
        return self.is_element_visible(self.SOS_BUTTON) or self.is_element_visible(self.PROFILE_ICON)
