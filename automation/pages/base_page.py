from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.common.by import By
from selenium.webdriver.remote.webdriver import WebDriver
from selenium.webdriver.remote.webelement import WebElement
from automation.config.config import Config
from automation.utils.logger_util import logger
from automation.utils.screenshot_util import take_screenshot

class BasePage:
    def __init__(self, driver: WebDriver):
        self.driver = driver
        self.wait = WebDriverWait(driver, Config.EXPLICIT_WAIT)

    def navigate_to(self, path: str = ""):
        url = self.driver.current_url
        target_url = f"{Config.BASE_URL}{path}"
        logger.info(f"Navigating from {url} to {target_url}")
        self.driver.get(target_url)

    def wait_for_element_visible(self, locator: tuple) -> WebElement:
        logger.debug(f"Waiting for element {locator} to be visible")
        return self.wait.until(EC.visibility_of_element_located(locator))

    def wait_for_element_clickable(self, locator: tuple) -> WebElement:
        logger.debug(f"Waiting for element {locator} to be clickable")
        return self.wait.until(EC.element_to_be_clickable(locator))

    def click_element(self, locator: tuple):
        try:
            element = self.wait_for_element_clickable(locator)
            element.click()
            logger.info(f"Clicked on element {locator}")
        except Exception as e:
            logger.error(f"Failed to click on element {locator}: {str(e)}")
            take_screenshot(self.driver, f"click_failed_{locator[1]}")
            raise e

    def enter_text(self, locator: tuple, text: str):
        try:
            element = self.wait_for_element_visible(locator)
            element.clear()
            element.send_keys(text)
            logger.info(f"Entered text '{text}' into element {locator}")
        except Exception as e:
            logger.error(f"Failed to enter text into element {locator}: {str(e)}")
            take_screenshot(self.driver, f"enter_text_failed_{locator[1]}")
            raise e

    def get_element_text(self, locator: tuple) -> str:
        try:
            element = self.wait_for_element_visible(locator)
            text = element.text
            logger.info(f"Retrieved text '{text}' from element {locator}")
            return text
        except Exception as e:
            logger.error(f"Failed to retrieve text from element {locator}: {str(e)}")
            take_screenshot(self.driver, f"get_text_failed_{locator[1]}")
            raise e

    def is_element_present(self, locator: tuple) -> bool:
        try:
            self.wait.until(EC.presence_of_element_located(locator))
            return True
        except Exception:
            return False

    def is_element_visible(self, locator: tuple) -> bool:
        try:
            self.wait.until(EC.visibility_of_element_located(locator))
            return True
        except Exception:
            return False

    def wait_for_flutter_load(self):
        """Waits for the Flutter application glass pane or canvas to be present in the DOM."""
        logger.info("Waiting for Flutter Web application to bootstrap...")
        # Flutter Web mounts inside a tag named <flt-glass-pane> or a canvas
        locator = (By.TAG_NAME, "flt-glass-pane")
        canvas_locator = (By.TAG_NAME, "canvas")
        
        try:
            self.wait.until(
                lambda d: d.find_elements(*locator) or d.find_elements(*canvas_locator)
            )
            logger.info("Flutter Web application loaded in the DOM.")
        except Exception as e:
            logger.error("Timeout waiting for Flutter Web application load.")
            take_screenshot(self.driver, "flutter_load_failed")
            raise e
            
    def get_browser_logs(self):
        """Retrieves and returns browser console logs."""
        try:
            return self.driver.get_log("browser")
        except Exception as e:
            logger.debug(f"Could not retrieve browser logs: {str(e)}")
            return []
