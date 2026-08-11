# Running and demoing MedIntel Nexus

## What it is, in four sentences

MedIntel Nexus is an Android app that scans prescriptions and lab reports,
extracts what they say with OCR, checks the medicines against a drug
interaction dataset, and answers health questions.

Every AI call goes to a model running on our own server, not a hosted
provider. That is a deliberate constraint, not a limitation: this handles
prescriptions, lab results and health conversations, and none of it should
leave the deployment. The tradeoff is that the server has to be running and
reachable for the AI features to work.

## The two halves

| | Where it runs | What it is |
|---|---|---|
| App | The phone | Flutter, Riverpod, go_router. Camera, alarms, SOS, biometrics |
| Backend | A machine you control | FastAPI, Tesseract OCR, DDInter dataset, Ollama running `qwen2.5:7b-instruct` |

The phone talks to the backend over HTTP. It finds it by sweeping the local
subnet for something answering `/health`, because a laptop's address changes
with every network — or you set the address by hand in Profile → server
settings, which is what you do for an address that doesn't move.

## Starting it

**1. The model** (once per boot)

```bash
ollama serve
```

**2. The backend**

```bash
cd medintel-nexus-backend
./scripts/run.sh
```

It prints the URL the phone should use. `run.sh` binds `0.0.0.0` — the
default `127.0.0.1` serves only the machine itself, and every request from
the phone is refused before it reaches Python.

Check both halves:

```bash
curl localhost:8000/health       # the API
curl localhost:8000/health/llm   # the model, and what's wrong if it isn't up
```

**3. The app**

```bash
flutter run                                     # with a device attached
flutter build apk --release --split-per-abi     # installable build
```

The APK to install is `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.
Split per ABI because the on-device inference libraries ship for three
architectures, and a combined build is 226 MB against 112 MB.

## Reaching the backend from the phone

| Phone is on | What works |
|---|---|
| Same Wi-Fi | Nothing to do — the app finds the backend by sweeping the subnet |
| USB cable | `adb reverse tcp:8000 tcp:8000`, then the app reaches it at `localhost:8000` |
| Mobile data | Tailscale on both machines, then set `http://<mac's 100.x.y.z>:8000` in Profile → server settings |

A typed-in address is never overwritten by automatic detection, so a
Tailscale address survives moving between networks.

If the phone can't reach it and all of the above is right, the usual causes
are the router isolating clients from each other, or a firewall on the
backend machine.

## What needs the model, and what doesn't

Useful to know when the model is slow or not running — the app degrades
rather than inventing values, so these fail differently.

| Works without the model | Needs the model |
|---|---|
| Nearby pharmacies (OpenStreetMap proxy) | Assistant chat |
| Drug interactions (DDInter dataset) | Symptom check |
| OCR text extraction (Tesseract) | Generic swap |
| Patient records, reminders, SOS | Turning a report's text into metrics |

Report structuring against a real multi-page lab PDF takes around three
minutes on CPU. That is the model, not the pipeline.

## Demoing it

Have `ollama serve` and `./scripts/run.sh` running before you start, and
check `/health/llm` — a scan that comes back "couldn't read this" looks
identical whether the photo was bad or the model is down.

The features that show best are the ones that don't wait on the model:
scanning a prescription, the interaction check, and nearby pharmacies.
Start the report analysis early if you plan to show it, because three
minutes is a long silence in front of an audience.
