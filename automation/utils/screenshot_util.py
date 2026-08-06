import os
import time
from selenium.webdriver.remote.webdriver import WebDriver
from automation.config.config import Config
from automation.utils.logger_util import logger

def take_screenshot(driver: WebDriver, name: str) -> str:
    """Captures a screenshot and saves it to the reports folder.
    Returns the absolute path to the saved screenshot file.
    """
    try:
        os.makedirs(Config.SCREENSHOTS_DIR, exist_ok=True)
        timestamp = int(time.time() * 1000)
        safe_name = "".join([c if c.isalnum() or c in ("-", "_") else "_" for c in name])
        filename = f"{safe_name}_{timestamp}.png"
        filepath = os.path.join(Config.SCREENSHOTS_DIR, filename)
        
        driver.save_screenshot(filepath)
        logger.debug(f"Screenshot captured and saved to: {filepath}")
        return filepath
    except Exception as e:
        logger.error(f"Failed to capture screenshot '{name}': {str(e)}")
        return ""
