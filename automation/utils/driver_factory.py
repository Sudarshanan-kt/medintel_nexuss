from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from automation.config.config import Config
from automation.utils.logger_util import logger

class DriverFactory:
    @staticmethod
    def get_chrome_driver() -> webdriver.Chrome:
        """Configures and returns a Chrome WebDriver instance optimized for headless CI/CD execution."""
        logger.info("Initializing Chrome WebDriver with enterprise options...")
        
        options = Options()
        # Headless mode (modern 'new' headless implementation)
        options.add_argument("--headless=new")
        options.add_argument("--no-sandbox")
        options.add_argument("--disable-dev-shm-usage")
        options.add_argument("--disable-gpu")
        options.add_argument("--window-size=1280,1024")
        
        # Security/CORS and Mixed-Content options to allow HTTPS -> local HTTP interactions
        options.add_argument("--allow-running-insecure-content")
        options.add_argument("--ignore-certificate-errors")
        options.add_argument("--disable-web-security")
        options.add_argument("--disable-features=IsolateOrigins,site-per-process")
        
        # Additional headless optimizations
        options.add_argument("--blink-settings=imagesEnabled=true") # Load images for screenshot audits
        
        try:
            driver = webdriver.Chrome(options=options)
            driver.implicitly_wait(Config.IMPLICIT_WAIT)
            logger.info("Chrome WebDriver initialized successfully.")
            return driver
        except Exception as e:
            logger.error(f"Failed to start Chrome WebDriver: {str(e)}")
            raise e
