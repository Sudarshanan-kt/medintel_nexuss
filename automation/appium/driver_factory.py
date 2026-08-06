"""Appium driver construction for the native Android build of MedIntel Nexus.

The suite targets the debug APK produced by `flutter build apk --debug`. In CI the suite is
collected but not executed (no emulator on the runner), so every Appium import is kept lazy —
importing this module must never fail on a machine without the Appium client installed.
"""

import os
import socket
from urllib.parse import urlparse

from automation.config.config import Config
from automation.utils.logger_util import logger


def appium_server_available(timeout: float = 1.5) -> bool:
    """True when an Appium server is listening and the client library is importable.

    Used to skip the suite on machines (including CI runners) with no device attached.
    """
    try:
        import appium  # noqa: F401
    except ImportError:
        logger.info("Appium client library is not installed; native suite will be skipped.")
        return False

    parsed = urlparse(Config.APPIUM_SERVER_URL)
    host = parsed.hostname or "127.0.0.1"
    port = parsed.port or (443 if parsed.scheme == "https" else 4723)

    try:
        with socket.create_connection((host, port), timeout=timeout):
            logger.info(f"Appium server reachable at {host}:{port}.")
            return True
    except OSError:
        logger.info(f"No Appium server at {host}:{port}; native suite will be skipped.")
        return False


def build_capabilities() -> dict:
    """UiAutomator2 capabilities for the Flutter debug APK."""
    app_path = os.path.abspath(Config.APPIUM_APP_PATH)

    capabilities = {
        "platformName": "Android",
        "appium:automationName": "UiAutomator2",
        "appium:deviceName": Config.APPIUM_DEVICE_NAME,
        "appium:appPackage": Config.APPIUM_APP_PACKAGE,
        "appium:autoGrantPermissions": True,
        "appium:newCommandTimeout": 300,
        "appium:noReset": False,
        # Flutter renders to a single canvas, so widget-level waits come from the
        # appium-flutter-driver bridge rather than the native accessibility tree.
        "appium:settings[waitForIdleTimeout]": 1000,
    }

    if os.path.exists(app_path):
        capabilities["appium:app"] = app_path
    else:
        logger.warning(
            f"APK not found at {app_path}; relying on the app already being installed on the device."
        )

    if Config.APPIUM_PLATFORM_VERSION:
        capabilities["appium:platformVersion"] = Config.APPIUM_PLATFORM_VERSION

    return capabilities


def create_driver():
    """Instantiates a remote Appium session. Only call when appium_server_available() is True."""
    from appium import webdriver
    from appium.options.android import UiAutomator2Options

    options = UiAutomator2Options().load_capabilities(build_capabilities())
    logger.info(f"Starting Appium session against {Config.APPIUM_SERVER_URL}...")

    driver = webdriver.Remote(Config.APPIUM_SERVER_URL, options=options)
    driver.implicitly_wait(Config.IMPLICIT_WAIT)
    logger.info("Appium session established.")
    return driver
