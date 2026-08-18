# MedIntel Nexus — Multi-Service Startup & Developer Guide

Welcome to the **MedIntel Nexus** development workspace! This guide serves as the single source of truth for setting up, configuring, running, and verifying all components of the MedIntel Nexus ecosystem.

The application is structured into four main operational layers:
1. **Frontend Client**: Flutter mobile (Android/iOS) and web application.
2. **REST API Backend**: FastAPI service running OCR, routing local LLM requests, and checking drug interactions.
3. **Database & Auth (Supabase)**: Cloud/local Supabase instance running Postgres, managing Care Circles, RLS policies, and periodic notification edge functions.
4. **Local LLM & OCR Services**: Ollama (serving Qwen2.5 7B server-side) and Deno (sideloaded LiteRT Qwen2.5 1.5B on-device), plus Tesseract OCR.

---

## 🗺️ Service Topology & Data Flows

Below is the network and service connectivity structure of MedIntel Nexus:

```mermaid
graph TD
    %% Clients
    subgraph Client [Client Application Layer]
        FlutterApp["Flutter Mobile Client (Android/iOS)"]
        FlutterWeb["Flutter Web App"]
    end

    %% API Backend
    subgraph API [FastAPI Backend Service]
        FastAPIApp["FastAPI Server (Port 8000)"]
        TesseractEngine["Tesseract OCR Engine"]
        DDInterDB[(SQLite DDInter DB)]
    end

    %% Local LLM
    subgraph LLM [Local LLM Engine]
        OllamaServer["Ollama Daemon (Port 11434)"]
        Qwen7B["Model: qwen2.5:7b-instruct"]
    end

    %% Database & Auth
    subgraph DatabaseAuth [Supabase Platform]
        SupaDb[(PostgreSQL Database)]
        SupaAuth["Supabase Auth / JWT Validation"]
        EdgeCron["Edge Function: send-missed-dose-alerts (Deno)"]
    end

    %% External Systems
    subgraph GoogleFirebase [Google & Firebase]
        FcmService["Firebase Cloud Messaging (FCM)"]
        GoogleConsole["Google Sign-In API"]
    end

    %% Connections
    FlutterApp -->|Sweeps Subnet / REST API| FastAPIApp
    FlutterWeb -->|REST API| FastAPIApp
    FlutterApp -->|Direct HTTPS Auth/DB Sync| SupaAuth
    FlutterApp -->|Direct DB Sync| SupaDb

    FastAPIApp -->|Validate JWTs| SupaAuth
    FastAPIApp -->|Inference Requests (OpenAI API Shape)| OllamaServer
    OllamaServer -->|Loads| Qwen7B
    FastAPIApp -->|Executes OCR| TesseractEngine
    FastAPIApp -->|Reads Safety Data| DDInterDB

    EdgeCron -->|Read Logs & Members| SupaDb
    EdgeCron -->|FCM Push Notifications| FcmService
    FcmService -.->|Alert Delivery| FlutterApp
    FlutterApp -->|Google Authentication| GoogleConsole
```

---

## 🛠️ Global Prerequisites Check

Before starting, install the native tools required by the backend, local inference engine, and the automation suites:

| Tool / Dependency | Version | Installation Command (macOS) | Installation Command (Linux / Debian) |
|---|---|---|---|
| **Homebrew** | Stable | `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` | — |
| **Python** | 3.10+ | `brew install python` | `sudo apt install python3-pip python3-venv` |
| **Tesseract OCR** | Stable | `brew install tesseract` | `sudo apt install tesseract-ocr` |
| **Ollama** | Latest | `brew install ollama` | `curl -fsSL https://ollama.com/install.sh | sh` |
| **Flutter SDK** | Stable | Install via `fvm` or [flutter.dev](https://flutter.dev) | Follow Flutter install guide |
| **Docker** | Latest | Install Docker Desktop | `sudo apt install docker.io docker-compose` |
| **Node.js & NPM** | 18+ | `brew install node` | `sudo apt install nodejs npm` |

---

## 🚀 Service Setup Checklists

Follow these steps in order to start and verify the services.

### Service 1: Local LLM Engine (Ollama)
The FastAPI backend depends on a local Ollama daemon for text structuring, system symptom verification, and assistant chat.

1. **Launch the Ollama daemon**:
   ```bash
   ollama serve
   ```
   *(Keep this terminal running or run Ollama as a background service/app)*.

2. **Pull the required model**:
   ```bash
   ollama pull qwen2.5:7b-instruct
   ```
   This is a one-time ~4.7 GB download.

3. **Verify running status**:
   Ensure it is listening on port `11434`:
   ```bash
   curl http://localhost:11434
   # Should return: "Ollama is running"
   ```

---

### Service 2: Database, Auth, and Edge Tasks (Supabase)
Supabase handles user accounts, active medicines list, dose logs, device tokens, and care circle links.

#### A. Database Schema Initialization
You can initialize the Supabase schema using one of two methods:
1. **Using Supabase Local CLI (Preferred for local development)**:
   ```bash
   supabase init
   supabase start
   ```
   *(Applies migrations located in the [supabase/migrations](file:///Users/sudarshanankt/dev/medintel_nexus/supabase/migrations) directory automatically)*.
2. **Using the Supabase Cloud Console**:
   If using the cloud version, copy the contents of the files in [supabase/migrations](file:///Users/sudarshanankt/dev/medintel_nexus/supabase/migrations) in sequential order and execute them inside the **SQL Editor** on your Supabase dashboard:
   - [20260810090000_core_patient_tables.sql](file:///Users/sudarshanankt/dev/medintel_nexus/supabase/migrations/20260810090000_core_patient_tables.sql)
   - [20260810090100_care_circle.sql](file:///Users/sudarshanankt/dev/medintel_nexus/supabase/migrations/20260810090100_care_circle.sql)
   - [20260810090200_care_circle_tasks.sql](file:///Users/sudarshanankt/dev/medintel_nexus/supabase/migrations/20260810090200_care_circle_tasks.sql)
   - [20260810090300_device_tokens.sql](file:///Users/sudarshanankt/dev/medintel_nexus/supabase/migrations/20260810090300_device_tokens.sql)
   - [20260810090400_care_circle_invite_hardening.sql](file:///Users/sudarshanankt/dev/medintel_nexus/supabase/migrations/20260810090400_care_circle_invite_hardening.sql)

#### B. Configure Auth Redirect URLs
Configure deep-linking redirect schemes inside your Supabase project dashboard (**Authentication → URL Configuration**):
- **Redirect URL**: `medintel-nexus://login-callback`

#### C. Deploy the Missed-Dose Alerts Edge Function
The Deno-based scheduled edge function [index.ts](file:///Users/sudarshanankt/dev/medintel_nexus/supabase/functions/send-missed-dose-alerts/index.ts) checks for missed doses and alerts care circles:
1. **Set Firebase Cloud Messaging Secret**:
   Generate a private key JSON from **Firebase Console → Project Settings → Service Accounts** and upload it:
   ```bash
   supabase secrets set FCM_SERVICE_ACCOUNT_JSON='<paste-full-json-content>'
   ```
2. **Deploy the function**:
   ```bash
   supabase functions deploy send-missed-dose-alerts
   ```
3. **Schedule the cron schedule**:
   Set up the cron to fire every 5 minutes (`*/5 * * * *`) on your Supabase Edge Functions dashboard, or execute:
   ```bash
   supabase functions schedule --cron "*/5 * * * *" send-missed-dose-alerts
   ```

#### D. Running Security & RLS Tests
To run Row Level Security (RLS) policies tests against a mock Postgres engine locally:
```bash
# Start a clean postgres container
docker run -d --name medintel-pg-test -e POSTGRES_PASSWORD=pw -p 55432:5432 postgres:15-alpine

# Set up Supabase mock auth roles
docker exec medintel-pg-test psql -U postgres -q -c "create role authenticated nologin; create role anon nologin;"

# Copy schema migrations and tests to container
docker cp supabase/tests medintel-pg-test:/tmp/tests
docker cp supabase/migrations medintel-pg-test:/tmp/migrations

# Load auth shim & migration scripts
docker exec medintel-pg-test psql -U postgres -v ON_ERROR_STOP=1 -q -f /tmp/tests/00_auth_shim.sql
for f in $(ls supabase/migrations); do
  docker exec medintel-pg-test psql -U postgres -v ON_ERROR_STOP=1 -q -f /tmp/migrations/$f
done

# Run the RLS Policy assertions
docker exec medintel-pg-test psql -U postgres -q -f /tmp/tests/care_circle_rls_test.sql

# Clean up container
docker rm -f medintel-pg-test
```
*The assertion test code is defined in [care_circle_rls_test.sql](file:///Users/sudarshanankt/dev/medintel_nexus/supabase/tests/care_circle_rls_test.sql). If no errors are raised, all 13 RLS test scenarios have passed.*

---

### Service 3: REST API Backend (FastAPI)
The python backend handles drug interactions, pharmacy lookup, and OCR parsing.

1. **Enter backend directory and activate virtual environment**:
   ```bash
   cd medintel-nexus-backend
   python -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   ```

2. **Configure Environment Variables**:
   Copy [.env.example](file:///Users/sudarshanankt/dev/medintel_nexus/medintel-nexus-backend/.env.example) to `.env`:
   ```bash
   cp .env.example .env
   ```
   Edit `.env` and fill:
   - `SUPABASE_URL`: Your Supabase project URL.
   - `SUPABASE_JWT_SECRET`: Your Supabase HS256 secret (Project Settings → API).
   - `AUTH_DISABLED`: Set to `true` to skip tokens validation in local development (uses mock user `dev-user`).
   - `DISCOVERY_SECRET`: Generate a random hex string or use `188c22dafb79763bb2c179e3871b9680` to pair with local clients.

3. **Build the Drug Safety Database**:
   Run the parser [import_ddinter.py](file:///Users/sudarshanankt/dev/medintel_nexus/medintel-nexus-backend/scripts/import_ddinter.py) to build the safety database from DDInter:
   ```bash
   python scripts/import_ddinter.py
   ```
   *Note: This generates `data/ddinter.db` (approx. 8MB). Running the interaction checker without it will fail.*

4. **Launch the FastAPI Server**:
   Always run using [run.sh](file:///Users/sudarshanankt/dev/medintel_nexus/medintel-nexus-backend/scripts/run.sh) (or bind `0.0.0.0` manually) to expose it to the local subnet:
   ```bash
   ./scripts/run.sh --port 8000
   ```

5. **Verify Backend Services**:
   ```bash
   curl localhost:8000/health       # Checks REST API
   curl localhost:8000/health/llm   # Checks if Ollama is connected & reachable
   ```

---

### Service 4: Client Application (Flutter)
The UI shell is compiled/run locally and loaded on a physical phone or simulator.

1. **Get Dependencies**:
   ```bash
   flutter pub get
   ```

2. **Configure App Settings**:
   Copy [.env.example](file:///Users/sudarshanankt/dev/medintel_nexus/.env.example) to `.env` in the root:
   ```bash
   cp .env.example .env
   ```
   Edit `.env` and populate:
   - `SUPABASE_URL`: Matches backend `SUPABASE_URL`.
   - `SUPABASE_ANON_KEY`: Supabase Client Anon public key.
   - `GOOGLE_WEB_CLIENT_ID`: Web OAuth client ID from Google Console (used for Auth provider setup).
   - `DEMO_OTP_ON_SCREEN`: Set to `true` to display OTP verification codes directly in the app UI for testing without SMS providers.

3. **Run Client Application**:
   - For web preview:
     ```bash
     flutter run -d chrome
     ```
   - For interactive debugging on USB-connected device:
     ```bash
     flutter run
     ```

4. **Sideload APK & On-Device AI Model (Physical Android Devices)**:
   For local offline assistance chat, download the on-device LiteRT model task file (`qwen2.5-1.5b-it-q8.task`) and sideload it to the device directory:
   ```bash
   # Build release APK targeting local IP configuration
   flutter build apk --release --dart-define=API_BASE_URL=http://$(ipconfig getifaddr en0):8000

   # Deploy APK and push the offline 1.6GB model to SD Card
   ./scripts/install_to_phone.sh ~/Downloads/qwen2.5-1.5b-it-q8.task
   ```
   *(Pushed via [install_to_phone.sh](file:///Users/sudarshanankt/dev/medintel_nexus/scripts/install_to_phone.sh))*

---

## 🔗 Client-to-Backend Connectivity Guide

The Flutter mobile client communicates with the FastAPI backend over HTTP. Choose the appropriate binding mode:

### Mode A: Same Wi-Fi Network (Default)
1. Ensure the backend is run with [run.sh](file:///Users/sudarshanankt/dev/medintel_nexus/medintel-nexus-backend/scripts/run.sh) (binds to `0.0.0.0`).
2. Ensure the phone and host machine are on the exact same Wi-Fi subnet.
3. The client app will automatically sweep the local subnet (`/health`) to locate the backend.

### Mode B: USB Cable Connection
For reliable local testing without Wi-Fi subnet matching:
1. Connect the phone via USB.
2. Run port forwarding:
   ```bash
   adb reverse tcp:8000 tcp:8000
   ```
3. The app will communicate with the backend via `http://localhost:8000`.

### Mode C: Tailscale (Mobile Data)
If testing the phone client over cellular data:
1. Install Tailscale on the host machine and the mobile phone.
2. Retrieve the host machine's Tailscale IP (`100.x.y.z`).
3. Open the app, go to **Profile → Server Settings**, and enter `http://<tailscale-ip>:8000`.
4. Enter the matching `DISCOVERY_SECRET` in server settings.

---

## 🧪 Quality Assurance & E2E Testing

Verify the system using the automated Selenium, Load, and Security test suites:

### 1. Initialize Python Venv for Automation
```bash
# Create python venv at root level
python -m venv venv
source venv/bin/activate
pip install selenium pytest openpyxl requests uvicorn
```

### 2. Configure Environment Variables
```bash
export BASE_URL="https://sudarshanan-kt.github.io/medintel_nexuss/"
export BACKEND_URL="http://127.0.0.1:8000"
```

### 3. Run Test Suites
```bash
# Functional UI Suite (900 scenarios, Chrome needed)
SUITE=functional python -m pytest automation/tests/test_selenium.py -v

# Load & API Performance Suite (300 scenarios)
SUITE=performance python -m pytest automation/tests/test_load.py -v

# Security & Vulnerability Scanner Suite (300 scenarios)
SUITE=security python -m pytest automation/tests/test_vulnerability.py -v

# Native Device Suite (Appium)
# Note: Requires a running Appium server (appium --base-path /)
SUITE=appium python -m pytest automation/tests/test_appium.py -v
```
*(Functional tests are set up in [test_selenium.py](file:///Users/sudarshanankt/dev/medintel_nexus/automation/tests/test_selenium.py), performance tests in `test_load.py`, security tests in `test_vulnerability.py`, and appium tests in `test_appium.py`)*

### 4. Aggregate Quality Reports & Gates
```bash
python -m automation.utils.report_generator
python -m automation.utils.summary_generator
```
*(Executed via [report_generator.py](file:///Users/sudarshanankt/dev/medintel_nexus/automation/utils/report_generator.py) and [summary_generator.py](file:///Users/sudarshanankt/dev/medintel_nexus/automation/utils/summary_generator.py))*

*Open `automation/reports/HTML/dashboard.html` to review the results and the 95.00% pass SLA gate status.*

---

## 🛠️ Troubleshooting FAQ

#### Q: Port 8000 is already in use
Check for active processes listening on the port and terminate them:
```bash
lsof -i :8000
kill -9 <PID>
```

#### Q: The browser blocks backend requests during automation (Mixed Content / HTTPS-to-HTTP)
The Selenium automation drivers inside [driver_factory.py](file:///Users/sudarshanankt/dev/medintel_nexus/automation/utils/driver_factory.py) automatically launch Chrome with `--allow-running-insecure-content` and `--disable-web-security` flags. Do not modify these configs, as they permit the GitHub Pages HTTPS frontend to talk to the local backend HTTP server.

#### Q: Prescription scans return "could not read this"
- Make sure `ollama serve` is running and the model is fully loaded. Check `curl localhost:8000/health/llm`.
- Verify the SQLite database `medintel-nexus-backend/data/ddinter.db` is built. Run `python scripts/import_ddinter.py` if missing.
- Hand-written prescriptions are deliberately flagged as **unverified** inside the OCR safety gate to prevent clinical errors. Confirm the parsed text manually in the app.

#### Q: The on-device assistant status shows "Missing local model"
Ensure the `.task` model file is pushed to `/sdcard/Android/data/com.medintelnexus.medintel_nexus/files/qwen2.5-1.5b-it-q8.task`. If you do not have a physical device, the app degrades gracefully, using the local FastAPI server as a backup.
