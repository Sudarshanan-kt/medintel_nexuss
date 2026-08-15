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
subnet for a host that answers `/health` *and* proves it holds the backend's
pairing code, because a laptop's address changes with every network — or you
set the address by hand in Profile → server settings, which is what you do
for an address that doesn't move.

## Starting it

**1. The model** (once per boot)

```bash
ollama serve
```

**2. The backend**

```bash
cd medintel-nexus-backend
./scripts/run.sh                 # add --no-reload when demoing
```

It prints the URL the phone should use, and a **pairing code** — 32 hex
characters, generated into `.env` the first time and the same on every run
after that. Enter it in the app once (below). `run.sh` binds `0.0.0.0` — the
default `127.0.0.1` serves only the machine itself, and every request from
the phone is refused before it reaches Python.

Two things that binding brings with it. Hot reload is on by default and
drops every open connection each time a file is saved, which in front of an
audience looks like a scan that failed for no reason — `--no-reload` is the
fix. And `AUTH_DISABLED=true` in `.env` would otherwise hand patient records
to anyone on the same Wi-Fi, so with that flag set the server answers only
its own machine and the phone gets 403s; `run.sh` says so on startup.

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

First, once per phone: Profile → server settings → **pairing code**, and
paste in what `run.sh` printed. Then:

| Phone is on | What works |
|---|---|
| Same Wi-Fi | Nothing more to do — the app finds the backend by sweeping the subnet |
| USB cable | `adb reverse tcp:8000 tcp:8000`, then the app reaches it at `localhost:8000` |
| No shared Wi-Fi | Turn on the phone's hotspot and join the laptop to it. That puts both on one subnet, so the sweep works as it does on any other Wi-Fi |

The hotspot case is the one to reach for away from a network you control.
Nothing is installed, no account is involved, and the traffic goes phone →
laptop directly rather than out to the internet and back — which matters
here, because it is prescriptions and lab results. The laptop borrows the
phone's mobile data for its own traffic; the app and the backend never use
it. Restart `run.sh` after joining, so it prints the hotspot address rather
than the old one.

If the phone can't reach it and all of the above is right, the usual causes
are the router isolating clients from each other, or a firewall on the
backend machine. A typed-in address is never overwritten by automatic
detection, so an address that works off-LAN — a tunnel, a real deployment —
survives moving between networks.

### Why the pairing code exists

The subnet sweep has to pick one host out of 254, and "answered `/health`"
is not evidence: on café, hospital or campus Wi-Fi, anything can return
`{"status": "ok"}` on port 8000, and whatever the app adopted would then
receive a Supabase bearer token, prescriptions and lab results. The sweep
used to take the first host that replied.

Now each candidate is sent a random nonce and has to return
`HMAC-SHA256(pairing code, nonce)`. The code never crosses the network, the
answer is different every time so there is nothing worth overhearing, and a
host that can't produce it is passed over. No code entered means no sweep at
all — the app asks for an address rather than guessing at one.

Two things this deliberately does not do. It doesn't touch a typed-in or
compiled-in address: somebody named that host on purpose, so it is trusted
on their say-so and only the *guessing* is locked down. And it authenticates
the server, not the channel — the traffic is still plain HTTP, so anything
already positioned on the path can read it. Closing that needs TLS, which
needs a certificate the laptop doesn't have. USB (`adb reverse`) avoids
both problems and is the safest way to demo.

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

## Caregiver sign-in, without an SMS provider

Caregivers sign in with a six-digit code and no password. Out of the box the
screen says "Text-message sign-in is not configured yet" — that is Auth
refusing the request with `unsupported phone provider`, before any code is
generated.

Wiring up real SMS is not the small job it looks like. Twilio, MessageBird
and Vonage all refuse to deliver to an Indian number until the *sender* has
completed DLT registration with TRAI: a registered business entity, an
approved header, an approved template. For a demo, that is not worth it.

So the code is shown on screen instead of texted. Auth still generates it,
expires it and verifies it exactly as it would for a real message — a Send
SMS hook writes it to a table in this database rather than handing it to a
provider, and the app reads it back. A new code every sign-in, and a real
Supabase session at the end of it. Nothing is faked but delivery.

**1. Apply the migration**

`supabase/migrations/20260815193000_demo_otp_on_screen.sql` creates three
things: `demo_otp_phones` (the allowlist), `demo_otp_codes` (the latest code
per number), and `public.send_sms_hook`. Add each number you'll demo with to
the allowlist — digits only, no `+`:

```sql
insert into public.demo_otp_phones (phone, note)
values ('919876543210', 'my handset') on conflict do nothing;
```

**2. Dashboard → Authentication → Providers → Phone**

Switch the provider **on** — that alone clears the error above. Then **clear
the Test OTP field**: Auth checks that list before it reaches any hook, so a
number listed there gets a fixed code and the rotating one never runs.

**3. Dashboard → Authentication → Hooks → Send SMS hook**

Enable it, type Postgres, schema `public`, function `send_sms_hook`. The SMS
provider settings go inert once a hook is enabled, so the provider fields can
hold anything.

**4. `.env`**

```
DEMO_OTP_ON_SCREEN=true
```

The code step now shows a "Demo sign-in — no text message sent" banner with
the live code in it. Anything other than `true` puts the normal SMS flow back
with no code on screen.

A number that isn't on the allowlist is refused by the hook, and the screen
says so rather than showing a provider error.

Two things worth knowing. SMS OTP Expiry is 60 seconds by default, which is
tight when you're reading a code off a projector — raise it on the Phone
panel if a demo runs long. And a code readable without a session is a code
anyone with the anon key can read, which is enough to sign in as that number:
keep the allowlist to numbers you own, and take `DEMO_OTP_ON_SCREEN` out of
`.env` before this build goes near anybody's real health data.

## Demoing it

Have `ollama serve` and `./scripts/run.sh` running before you start, and
check `/health/llm` — a scan that comes back "couldn't read this" looks
identical whether the photo was bad or the model is down.

The features that show best are the ones that don't wait on the model:
scanning a prescription, the interaction check, and nearby pharmacies.
Start the report analysis early if you plan to show it, because three
minutes is a long silence in front of an audience.
