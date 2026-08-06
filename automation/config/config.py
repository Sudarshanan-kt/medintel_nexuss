import os

class Config:
    # Target URL for end-to-end testing (never localhost/preview url unless explicitly instructed)
    # The default conforms to: https://<github-username>.github.io/<repository-name>/
    BASE_URL = os.getenv("BASE_URL", "https://sudarshanankt.github.io/medintel_nexus/").rstrip("/") + "/"
    
    # Backend URL for background server access during testing
    BACKEND_URL = os.getenv("BACKEND_URL", "http://localhost:8000")
    
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
    
    # Parallel execution partition index (0 to 4)
    JOB_INDEX = int(os.getenv("JOB_INDEX", "0"))
    TOTAL_JOBS = int(os.getenv("TOTAL_JOBS", "5"))
    TESTS_PER_JOB = int(os.getenv("TESTS_PER_JOB", "300"))
