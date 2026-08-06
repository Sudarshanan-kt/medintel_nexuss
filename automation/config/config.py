import os


def _normalise_base_url(raw: str) -> str:
    """Guarantees exactly one trailing slash so that f"{BASE_URL}asset.js" always resolves."""
    return raw.rstrip("/") + "/"


class Config:
    # Target URL for end-to-end testing. In CI this is supplied by the deploy job from the
    # actions/deploy-pages `page_url` output, so the owner/repo casing is never guessed.
    # The local default matches the real published site.
    BASE_URL = _normalise_base_url(
        os.getenv("BASE_URL", "https://sudarshanan-kt.github.io/medintel_nexuss/")
    )

    # Backend URL for background server access during testing
    BACKEND_URL = os.getenv("BACKEND_URL", "http://localhost:8000").rstrip("/")

    # Selenium settings
    IMPLICIT_WAIT = int(os.getenv("IMPLICIT_WAIT", "10"))
    EXPLICIT_WAIT = int(os.getenv("EXPLICIT_WAIT", "20"))

    # Path configuration
    BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    REPORTS_DIR = os.path.join(BASE_DIR, "reports")
    SCREENSHOTS_DIR = os.path.join(REPORTS_DIR, "Screenshots")
    LOGS_DIR = os.path.join(REPORTS_DIR, "Logs")
    EXCEL_DIR = os.path.join(REPORTS_DIR, "Excel")
    HTML_DIR = os.path.join(REPORTS_DIR, "HTML")
    JSON_DIR = os.path.join(REPORTS_DIR, "JSON")
    SUMMARY_DIR = os.path.join(REPORTS_DIR, "Summary")

    # Which suite this process is running. Scenarios in automation/data/scenarios.py carry a
    # "type" field ("functional" | "performance" | "security"); each suite selects its own slice
    # so the five CI jobs run genuinely different tests rather than shards of one list.
    SUITE = os.getenv("SUITE", "functional")

    # Optional sharding *within* a single suite. The functional suite is large enough that CI
    # splits it across a few runners; the smaller suites leave these at their defaults.
    SHARD_INDEX = int(os.getenv("SHARD_INDEX", "0"))
    SHARD_TOTAL = int(os.getenv("SHARD_TOTAL", "1"))

    # Appium (native Android) settings. The suite is skipped unless a server is reachable.
    APPIUM_SERVER_URL = os.getenv("APPIUM_SERVER_URL", "http://127.0.0.1:4723")
    APPIUM_APP_PATH = os.getenv("APPIUM_APP_PATH", "build/app/outputs/flutter-apk/app-debug.apk")
    APPIUM_DEVICE_NAME = os.getenv("APPIUM_DEVICE_NAME", "Android Emulator")
    APPIUM_PLATFORM_VERSION = os.getenv("APPIUM_PLATFORM_VERSION", "")
    APPIUM_APP_PACKAGE = os.getenv("APPIUM_APP_PACKAGE", "com.medintelnexus.medintel_nexus")

    @classmethod
    def shard(cls, items: list) -> list:
        """Returns this runner's slice of `items` using round-robin striping.

        Striping (rather than contiguous blocks) keeps each shard's mix of priorities and
        modules representative, so a partial run is still a meaningful sample.
        """
        if cls.SHARD_TOTAL <= 1:
            return items
        return [item for index, item in enumerate(items) if index % cls.SHARD_TOTAL == cls.SHARD_INDEX]

    @classmethod
    def result_file_name(cls) -> str:
        """Unique per-suite, per-shard intermediate results filename."""
        return f"results_{cls.SUITE}_{cls.SHARD_INDEX}.json"
