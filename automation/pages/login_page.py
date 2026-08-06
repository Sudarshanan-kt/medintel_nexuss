from selenium.webdriver.common.by import By
from automation.pages.base_page import BasePage
from automation.utils.logger_util import logger

class LoginPage(BasePage):
    # Selectors for Flutter Web inputs and elements
    # Since Flutter compiles inputs to HTML, we can locate inputs using tag name or relative selectors
    EMAIL_INPUT = (By.CSS_SELECTOR, "input[type='email']")
    PASSWORD_INPUT = (By.CSS_SELECTOR, "input[type='password']")
    LOGIN_BUTTON = (By.XPATH, "//*[contains(text(), 'Log In') or @aria-label='Log In']")
    SIGN_UP_LINK = (By.XPATH, "//*[contains(text(), 'Sign Up')]")
    ERROR_BANNER = (By.XPATH, "//*[contains(text(), 'incorrect') or contains(text(), 'failed') or contains(text(), 'invalid')]")

    def enter_email(self, email: str):
        logger.info(f"Entering email: {email}")
        self.enter_text(self.EMAIL_INPUT, email)

    def enter_password(self, password: str):
        logger.info("Entering password.")
        self.enter_text(self.PASSWORD_INPUT, password)

    def click_login(self):
        logger.info("Clicking the login button.")
        self.click_element(self.LOGIN_BUTTON)

    def login(self, email: str, password: str):
        self.wait_for_flutter_load()
        self.enter_email(email)
        self.enter_password(password)
        self.click_login()

    def navigate_to_signup(self):
        logger.info("Navigating to SignUp screen.")
        self.click_element(self.SIGN_UP_LINK)

    def get_error_message(self) -> str:
        if self.is_element_visible(self.ERROR_BANNER):
            return self.get_element_text(self.ERROR_BANNER)
        return ""
