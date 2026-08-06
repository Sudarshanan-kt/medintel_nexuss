from selenium.webdriver.common.by import By
from automation.pages.base_page import BasePage
from automation.utils.logger_util import logger

class PrescriptionScanPage(BasePage):
    # Selectors for file upload and scanning triggers
    UPLOAD_ZONE = (By.XPATH, "//*[contains(text(), 'Upload') or contains(text(), 'Choose File')]")
    FILE_INPUT = (By.CSS_SELECTOR, "input[type='file']")
    START_OCR_BTN = (By.XPATH, "//*[contains(text(), 'Analyze') or contains(text(), 'Start OCR')]")
    SCAN_RESULT_TITLE = (By.XPATH, "//*[contains(text(), 'Scan Results') or contains(text(), 'Detected Medicines')]")
    
    def upload_prescription_file(self, file_path: str):
        logger.info(f"Uploading file {file_path} into scanner input field.")
        self.enter_text(self.FILE_INPUT, file_path)

    def trigger_ocr_analysis(self):
        logger.info("Triggering OCR prescription analysis.")
        self.click_element(self.START_OCR_BTN)

    def is_scan_result_displayed(self) -> bool:
        logger.info("Checking for scan result interface.")
        return self.is_element_visible(self.SCAN_RESULT_TITLE)
