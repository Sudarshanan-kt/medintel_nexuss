import logging
import os
import sys
from automation.config.config import Config

class CustomLogger:
    _logger = None

    @classmethod
    def get_logger(cls):
        if cls._logger is None:
            # Ensure log directory exists
            os.makedirs(Config.LOGS_DIR, exist_ok=True)
            log_file = os.path.join(Config.LOGS_DIR, "automation.log")

            # Setup logger
            logger = logging.getLogger("MedIntelAutomation")
            logger.setLevel(logging.DEBUG)

            # Create formatter
            formatter = logging.Formatter(
                '%(asctime)s - %(levelname)s - [%(filename)s:%(lineno)d] - %(message)s'
            )

            # File Handler
            file_handler = logging.FileHandler(log_file, encoding='utf-8')
            file_handler.setLevel(logging.DEBUG)
            file_handler.setFormatter(formatter)

            # Console Handler
            console_handler = logging.StreamHandler(sys.stdout)
            console_handler.setLevel(logging.INFO)
            console_handler.setFormatter(formatter)

            # Avoid double logs
            logger.handlers = []
            logger.addHandler(file_handler)
            logger.addHandler(console_handler)
            logger.propagate = False

            cls._logger = logger
        return cls._logger

logger = CustomLogger.get_logger()
