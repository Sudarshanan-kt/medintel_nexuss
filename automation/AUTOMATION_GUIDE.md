# MedIntel Nexus — Automation, Deployment & Quality Reporting Guide

This guide details the layout, execution, and troubleshooting steps for the enterprise test automation framework and the continuous integration/continuous deployment (CI/CD) pipeline.

---

## 📂 Project Directory Structure

The framework is structured as follows:

```
automation/
├── AUTOMATION_GUIDE.md      # This documentation guide
├── config/
│   └── config.py            # Environment-driven settings loader (BASE_URL, wait times)
├── data/
│   ├── scenarios.py         # Programmatic registry of 1,500 unique test scenarios
│   └── test_data.py         # Static and dynamic credentials and testing payloads
├── pages/
│   ├── base_page.py         # Shared Selenium wrapper utilities (explicit waits, etc.)
│   ├── login_page.py        # Authentication POM
│   ├── dashboard_page.py    # Main Patient Dashboard and menu routing POM
│   └── prescription_scan_page.py # Upload scanner and OCR analysis POM
├── tests/
│   ├── conftest.py          # Pytest fixtures and failure hook captures
│   └── test_selenium.py     # Main parallelized test runner slice
└── utils/
    ├── driver_factory.py    # Headless Chrome driver initialization factory
    ├── logger_util.py       # Custom double-output logger utility
    ├── report_generator.py  # Excel & HTML dashboard aggregate reporter
    └── summary_generator.py # SLA gateway evaluation checker
```

---

## 💻 Local Execution Guide

To execute the automation framework on your local workstation:

### 1. Prerequisites
- **Python**: Ensure Python 3.10+ is installed.
- **Google Chrome**: Ensure a stable Chrome version is installed on the machine.
- **Flutter**: (Optional, only needed if building/running the app locally).

### 2. Installation & Setup
Initialize a virtual environment and install the required dependencies:

```bash
# Navigate to the workspace root directory
cd medintel_nexus

# Create a python virtual environment
python -m venv venv
source venv/bin/activate  # On Windows, use: venv\Scripts\activate

# Install dependencies for the automation suite and backend
pip install selenium pytest openpyxl requests uvicorn
cd medintel-nexus-backend && pip install -r requirements.txt && cd ..
```

### 3. Start the FastAPI Backend
Start the backend server in a separate terminal:

```bash
cd medintel-nexus-backend
source venv/bin/activate  # or venv\Scripts\activate
uvicorn main:app --reload --port 8000
```

### 4. Execute the Tests

The scenarios in `automation/data/scenarios.py` carry a `type` field, and each suite selects its
own slice. Always invoke pytest as `python -m pytest` from the repository root — the root
`pytest.ini` puts the repo on `sys.path` so `automation.*` imports resolve.

```bash
export BASE_URL="https://sudarshanan-kt.github.io/medintel_nexuss/"
export BACKEND_URL="http://127.0.0.1:8000"

# Selenium / functional suite (900 scenarios, needs Chrome)
SUITE=functional python -m pytest automation/tests/test_selenium.py -v

# Load / performance suite (300 scenarios, no browser)
SUITE=performance python -m pytest automation/tests/test_load.py -v

# Vulnerability / security suite (300 scenarios, no browser)
SUITE=security python -m pytest automation/tests/test_vulnerability.py -v
```

A large suite can be split across several terminals or machines with `SHARD_INDEX` /
`SHARD_TOTAL`. Shards are striped round-robin, so each one stays a representative sample:

```bash
SUITE=functional SHARD_INDEX=0 SHARD_TOTAL=3 python -m pytest automation/tests/test_selenium.py
SUITE=functional SHARD_INDEX=1 SHARD_TOTAL=3 python -m pytest automation/tests/test_selenium.py
SUITE=functional SHARD_INDEX=2 SHARD_TOTAL=3 python -m pytest automation/tests/test_selenium.py
```

Each run writes `automation/reports/JSON/results_<suite>_<shard>.json`.

### 5. Run the Native (Appium) Suite

The Appium suite needs a real device or emulator plus a running Appium server, so CI only
validates that it collects — you execute it locally:

```bash
pip install Appium-Python-Client
flutter build apk --debug

appium --base-path /            # in a second terminal

SUITE=appium python -m pytest automation/tests/test_appium.py -v
```

Without a reachable Appium server the suite skips cleanly rather than failing. Point it at a
different host or device with `APPIUM_SERVER_URL`, `APPIUM_DEVICE_NAME` and `APPIUM_APP_PATH`.

### 6. Generate and View Reports

After the suites have run, aggregate their results:

```bash
python -m automation.utils.report_generator
python -m automation.utils.summary_generator   # applies the SLA gate
```

If no suite produced results the aggregation **fails with exit code 1** rather than emitting a
report. This is deliberate — a quality report must only ever describe tests that actually ran.

Open `automation/reports/HTML/dashboard.html` in your web browser to view the interactive dashboard.

---

## 🚀 CI/CD Execution Guide

The CI/CD pipeline is implemented in `.github/workflows/deploy-and-test.yml`. It runs automatically on:
- Every `push` to `main` or `master` branches.
- Every `pull_request` targetting `main` or `master`.
- Manual trigger using the `workflow_dispatch` button in the actions panel.

### Workflow Execution Flow

Five suites run **in parallel**. `unit` and `appium` do not depend on the deployment, so they
start immediately; the three suites that exercise the live site wait for Pages to publish.

```mermaid
graph TD
    A[Trigger Event] --> B[Job: build]
    B -->|configure-pages + upload-pages-artifact| C[Job: deploy]
    C -->|deploy-pages, exports page_url| D[Deployment verified]

    A --> U[Suite: unit]
    A --> P[Suite: appium]
    D --> S[Suite: selenium x6 shards]
    D --> L[Suite: load]
    D --> V[Suite: vulnerability]

    U & S & L & V & P --> R[Job: report]
    R -->|Aggregate results_*.json| G[Generate HTML/Excel Reports]
    G -->|Validate Gateway SLA| M{95% Pass & <5% Crit Fail?}
    M -->|Yes| Y[Workflow Success & Publish Summary]
    M -->|No| N[Workflow Fail & Publish Summary]
```

| Suite | What it runs | Browser | Needs deploy |
|---|---|---|---|
| `unit` | `flutter test` + `flutter analyze` + backend `pytest` | no | no |
| `selenium` | 900 functional scenarios, 6 shards | yes | yes |
| `load` | 300 performance scenarios against the backend | no | yes |
| `vulnerability` | 300 security scenarios against the backend | no | yes |
| `appium` | builds the debug APK, validates the native suite collects | no | no |

The deployment uses the official `actions/configure-pages` → `upload-pages-artifact` →
`deploy-pages` chain with `enablement: true`, and `BASE_URL` is taken from the deployment's own
`page_url` output rather than assembled from the owner and repository names.

### SLA Quality Gates
The workflow evaluates SLA gates in the final job:
1. **Pass Rate**: Overall pass rate across all executed tests must be **at least 95.00%**.
2. **Critical Severity**: Failure rate of test cases marked as `Critical` must not exceed **5.00%**.
If either SLA condition fails, the pipeline exits with error code 1, marking the GitHub Actions run as failed.

The gate only ever evaluates results that were actually produced — if no suite wrote results,
the aggregation step fails rather than substituting a synthetic dataset.

---

## 🛠️ Troubleshooting Guide

### 1. Mixed Content Errors (HTTPS to HTTP)
- **Problem**: When Selenium loads the page from `https://sudarshanankt.github.io/medintel_nexus/`, Chrome may block requests to `http://localhost:8000` because the frontend is secure (HTTPS) and the local backend is insecure (HTTP).
- **Solution**: The framework configures Chrome options `--allow-running-insecure-content` and `--disable-web-security` inside `automation/utils/driver_factory.py` to bypass this block for local automation checks. Ensure these options are not deleted.

### 2. Chrome Sandbox Issues in Linux CI
- **Problem**: Chrome fails to start in Linux runner environments with permission errors.
- **Solution**: The webdriver setup uses the `--headless=new` and `--no-sandbox` flags. Do not remove `--no-sandbox` when running in Docker or virtual machines.

### 3. Missing Reports or Screenshots
- **Problem**: The final report contains broken screenshot or log links.
- **Solution**: The reports generation maps paths relative to `automation/reports`. In the CI pipeline, make sure artifacts are uploaded together using the path `automation/reports/` to keep directory links valid when downloaded.

### 4. Port 8000 Collision
- **Problem**: The FastAPI backend fails to start because port 8000 is already in use.
- **Solution**: Check running processes using `lsof -i :8000` on macOS/Linux and terminate the process.
