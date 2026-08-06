# MedIntel Nexus — Handoff Brief (Cowork → Claude Code)

## What this project is
MedIntel Nexus: AI-powered clinical intelligence & prescription risk analysis app.
Flutter client (patient app) + a planned FastAPI backend. State via Riverpod, nav via go_router, auth via Supabase.

## Current state

**Flutter app (`lib/`)** — fully scaffolded, these features already exist:
- `auth` — email login, sign up, forgot password, Google sign-in, biometric, onboarding
- `dashboard` — home screen, quick actions, app shell
- `scan` — prescription scanner + scan results
- `reports` — reports list, report viewer, OCR pipeline (currently backed by demo/synthetic data), health advice
- `reminders` — medicine reminders, alarms, local notifications
- `assistant` — AI chat + voice assistant
- `pharmacies` — nearby pharmacies via OpenStreetMap (flutter_map, no API key)
- `sos` — emergency SOS countdown/screen
- `profile` — health profile

**Backend (`medintel-nexus-backend/`) — NOT built yet.**
Only contains `requirements.txt` (FastAPI, Pydantic, PyJWT, httpx, structlog, redis, pytest) and an empty `venv/`. No `main.py`, no routes, no app code at all.

The Flutter side already assumes these backend routes exist (see `lib/core/network/api_endpoints.dart`), base URL defaults to `http://localhost:8000`:
- `GET /api/v1/patients/me`
- `POST /api/v1/prescriptions`, `/prescriptions/upload-url`, `/prescriptions/{id}`
- `/prescriptions/uploads`, `/prescriptions/uploads/{id}/complete`, `/prescriptions/{id}/medicines`, `/prescriptions/{id}/ocr`, `/prescriptions/{id}/reprocess`
- `/api/v1/reports`, `/api/v1/reports/{id}`
- `/api/v1/assistant/messages`, `/api/v1/assistant/stream/{id}`
- `/api/v1/interactions/check`
- `/api/v1/pharmacies/nearby`

Auth is currently handled directly by Supabase client-side (`lib/core/constants/supabase_config.dart`), not by the backend. A lot of "backend" behavior right now is actually mocked/local (demo OCR cache, synthetic reports, local rx store, shared_preferences).

## Agreed plan of work (in order)

1. **Build out the FastAPI backend first**, matching the routes Flutter already expects. This unblocks everything else that needs real server logic (OCR processing, drug-interaction checks, real AI assistant responses, persistent multi-device data).
2. **Add new features to the app.** (Specific feature list to be given directly in Claude Code — not yet finalized in this conversation.)
3. **Full UI redesign — do this last.** Direction given so far:
   - Background: greyish-white, not stark white
   - Floating medical/hospital-themed imagery (icons/illustrations) in the background of screens, at very low opacity — decorative, not distracting
   - Update the color palette app-wide once the new palette is chosen
   - Update login/signup screens (username + password fields, buttons) to match the new palette
   - User has design references/inspiration to share but hasn't pasted them into this conversation yet — ask for those before starting the redesign

## Immediate next step
Scaffold a minimal working FastAPI app in `medintel-nexus-backend/` (`main.py` + route stubs for the endpoints above) so `uvicorn main:app --reload --port 8000` actually runs, then flesh out real logic feature by feature.

## To run once scaffolded
```bash
cd medintel-nexus-backend
source venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```
