# MedIntel Nexus — backend

FastAPI service behind the Flutter client. Validates Supabase-issued JWTs
(it never mints its own), runs the prescription and lab-report OCR
pipelines, and serves the assistant.

## Everything runs locally

There is no hosted AI provider and no API key. Text extraction is Tesseract,
and every language-model call goes to a model running on this machine
through `app/llm.py`. That is a deliberate constraint: this handles
prescriptions, lab results and health conversations, and none of it should
be sent to a third party.

## Setup

```bash
# 1. Tesseract (OCR)
brew install tesseract          # macOS
# sudo apt install tesseract-ocr  # Debian/Ubuntu

# 2. The local model
brew install ollama             # or https://ollama.com/download
ollama serve                    # leave running
ollama pull qwen2.5:7b-instruct # one-time, ~4.7 GB

# 3. Python
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt

# 4. Run
./scripts/run.sh                 # or: uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

`--host 0.0.0.0` is not optional if a phone is involved. Uvicorn's default is
`127.0.0.1`, which accepts connections from this machine and nothing else —
the API answers `curl localhost:8000` perfectly while every request from the
phone is refused at the TCP level, on every Wi-Fi network. The app's own LAN
sweep can't find a server that isn't listening on the LAN either, so the
symptom is "pharmacies, generic swap and symptom check don't work here",
with no error pointing at the cause. `scripts/run.sh` binds correctly and
prints the URL the phone should use.

Binding `0.0.0.0` is also what makes everything below matter: the API is
reachable by everyone else on that Wi-Fi, not just the phone. Every route
requires a Supabase token, so that is a locked door — with one exception,
which is why `AUTH_DISABLED` now confines the server to localhost. See
"Running it openly" below.

Add `--no-reload` for demos. Hot reload drops every in-flight connection on
each file save, which the app surfaces as a scan that failed for no visible
reason.

It also prints a **pairing code**, generated into `.env` on first run. The
app checks it before adopting a server it found by scanning — a host that
merely answers `/health` could be anything on a shared network, and the app
has patient data and a bearer token to hand it. Enter the code once under
Profile → server settings; it doesn't change when the machine's IP does.

Check both halves are up:

```bash
curl localhost:8000/health       # the API
curl localhost:8000/health/llm   # the model — says what's wrong if it isn't
```

`/health/llm` exists because every LLM-backed feature degrades quietly by
design. A scan that comes back "couldn't read this" looks identical whether
the photo was bad or `ollama serve` isn't running; this tells you which.

Then confirm the phone's view of it, from another machine on the same Wi-Fi:

```bash
curl http://<this-machine's-LAN-IP>:8000/health
```

If that refuses while `localhost` works, the bind address is wrong. If it
hangs instead, a firewall or the router's client isolation is in the way.

## Reaching it from a phone

| Phone is on | What works |
|---|---|
| Any network at all | **Tailscale** on both devices, signed in to the same account. `run.sh` prints the `100.x.y.z` address; type it into Profile → server settings once. See below |
| Same Wi-Fi as this machine | Bind `0.0.0.0`, and enter the pairing code `run.sh` prints in the app once; it then finds this machine by sweeping the subnet |
| USB cable | `adb reverse tcp:8000 tcp:8000` — the app reaches it at `localhost:8000` |
| No shared Wi-Fi | Join this machine to the phone's hotspot. Both end up on one subnet and the sweep works normally; restart `run.sh` so it prints the new address |
| Neither is possible | A tunnel (`cloudflared tunnel --url http://localhost:8000`) or a real deployment, with the resulting public URL set in the app's server setting. Note this one routes patient data through a third party |

### Tailscale is the one that just keeps working

Everything else in that table depends on where the two devices happen to be.
The subnet sweep only finds a backend on the current Wi-Fi, and the address
it finds changes whenever DHCP reassigns it — so moving between home, campus
and mobile data means the app losing its backend each time, which surfaces as
pharmacies not loading and scans that never come back.

A Tailscale address does not move. Install Tailscale on this machine and on
the phone, sign both into the same account, then:

```bash
./scripts/run.sh          # prints "over Tailscale → http://100.x.y.z:8000"
```

Type that URL into the app under Profile → server settings. It sticks:
automatic detection never overwrites an address that was typed in, precisely
because it can only find things on the current LAN and would otherwise undo
this. No pairing code is needed for a typed-in address — the sweep is what
the code guards, and naming a host directly isn't guessing.

Two things it does not do. It is not faster: the traffic is the same and
report analysis is bounded by local inference, not the network. And it is
still plain HTTP inside the tunnel — though Tailscale encrypts device to
device, which is more than the LAN path offers.

## Configuration

Copy the settings you need into `.env` (gitignored). Every one has a working
default except the Supabase secret.

| Setting | Default | Notes |
|---|---|---|
| `SUPABASE_JWT_SECRET` | — | Required unless `AUTH_DISABLED=true` |
| `AUTH_DISABLED` | `false` | Dev only. Treats every caller as `dev-user`, and confines the API to localhost while it does |
| `DISCOVERY_SECRET` | generated | The pairing code. `run.sh` writes one on first run; leave it alone after that |
| `CORS_ORIGINS` | `[]` | Browser origins allowed to call this, e.g. `["http://localhost:5000"]`. Only the Flutter web build needs it |
| `LLM_BASE_URL` | `http://localhost:11434/v1` | Any OpenAI-compatible local server |
| `LLM_MODEL` | `qwen2.5:7b-instruct` | Must be pulled first |
| `LLM_API_KEY` | — | Ollama needs none; llama.cpp / LM Studio may |
| `LLM_TIMEOUT_SECONDS` | `180` | A 7B model on CPU is slow; don't cut this short |

Swapping to llama.cpp or LM Studio is a `LLM_BASE_URL` change and nothing
else — `app/llm.py` speaks the shape all of them implement.

## Running it openly

`AUTH_DISABLED=true` and an `0.0.0.0` bind are each reasonable on their own.
The flag lets you work before Supabase is configured; the bind is the only
way a phone can reach a laptop. Together they mean anyone on the same
network reads and writes patient records with `Authorization: Bearer
anything` — and "the same network" on campus or in a café is everybody.

So the server refuses the combination rather than either half: with
`AUTH_DISABLED=true` it answers requests from its own machine and returns
403 to everything else. Local development is unaffected. If the phone starts
getting 403s on every route, this is why — set `SUPABASE_JWT_SECRET` and
turn the flag off.

It is enforced per request in `main.py` rather than at startup, so it holds
however uvicorn was launched, including the by-hand command above.

The other thing an LAN-reachable server needs to get right is which websites
can script requests at it. `CORS_ORIGINS` is empty by default, which grants
nothing: the Android app is a native client, sends no `Origin`, and is
unaffected. Point the Flutter web build here and you have to name it —

```bash
flutter run -d chrome --web-port=5000     # then CORS_ORIGINS=["http://localhost:5000"]
```

— rather than reaching for `["*"]`. A wildcard here is not the harmless
catch-all it looks like. Starlette pairs it with `allow_credentials` by
echoing back whichever `Origin` asked instead of a literal `*`, so every
site on the internet ends up holding a credentialed grant against a server
on your home network. Credentials are now off outright, which forecloses
that: this API authenticates from a Bearer header and has never used
cookies.

Worth being clear about what this does not cover. The traffic is plain HTTP,
so the pairing code proves *which* server the app is talking to but keeps
nothing private from anything already on the path; `AUTH_DISABLED=false`
leaves the API open to unauthenticated `/health` and `/dev-storage` probes
from the LAN, which is intended; and none of it makes this deployable to the
public internet, which would need TLS and a real storage backend.

## Scans survive a restart

Uploads, prescriptions and reports live in `data/records.sqlite3` (created on
first use, gitignored). They used to be dicts in `app/store.py`, which meant
every restart — including each `--reload` file save — dropped every parsed
prescription and every lab-report analysis. The costly loss wasn't the image,
which was always on disk in `uploads/`; it was the OCR pass and local-model
round trip that turned it into structured medicines, and above all the
`verified` flag. A patient who had just read their prescription line by line
to confirm an uncertain drug name lost that and had to do it again.

`app/records_db.py` holds the schema and the record types; `app/store.py`
still owns the pipeline. Writes are whole-record upserts (`put_prescription`,
`put_report`), so **mutating a record object is no longer saving it** — the
background workers save in a `finally` so every exit path persists the status
it decided on.

The pharmacy cache lives there too. It used to be a dict, so every restart
threw away up to a day of results and sent the next search back to Overpass —
the opposite of what that project's usage policy asks, and slow precisely
where it shows. Measured across a real restart: 0.9s cold, then **28 ms** from
a brand-new process, same 45 results.

On startup the API resets anything still marked `queued` or `processing` to
`failed`. Those records outlived the process; the asyncio task working on
them didn't, and nothing restarts it, so a row left saying "processing" is a
client polling a status that will never change. `failed` is a state the app
already offers **Try again** on, which re-runs the pipeline over the stored
image.

## Two things worth knowing

**OCR cannot read handwriting reliably.** Not this engine, not a paid one.
Printed prescriptions and pharmacy labels work well; a doctor's cursive
often will not. Rather than hide that behind a made-up confidence number,
the pipeline measures it: `app/ocr.py` scores every extracted field against
the words Tesseract actually read, and a prescription with an uncertain drug
name or strength stays **unverified** until the patient confirms it.
`/interactions/check` refuses to run against an unverified prescription —
acting on a misread drug name is the worst failure this service has.

The thresholds in `app/ocr.py` are calibrated against measured Tesseract
output, not chosen a priori, so re-measure before moving them. On the same
prescription rendered twice: a legible capture scored 0.71–0.95 on drug
names and cleared the gate with nothing to confirm, while a degraded capture
scored 0.37–0.77 and held — including on `Warfarin 5mg`, which that run
genuinely misread as `WartarinSmg`. Be clear about what the number is: it
tracks how well the page supports the text, which is close to image quality.
It reliably separates "nothing on the page supports this" (a fabricated
medicine scores 0.0) from a real read, and it flags regions the OCR
struggled with — it does not rank correct readings above incorrect ones
within a single capture, and no confidence number can.

**A small local model is a weak clinical reasoner**, so it does not decide
anything clinical. It restructures text into a schema, rephrases, and holds
a conversation. Interaction verdicts come from data instead — see below.

## Drug interactions come from data, not the model

`/interactions/check` answers from DDInter 2.0 — a pairwise table of ~220k
graded drug pairs held in local SQLite. The model's only job is to explain,
in plain language, a pair the dataset has already confirmed and graded; it
cannot introduce an interaction, remove one, or change a severity.

That split exists because a verdict is a clinical claim. A model can't cite
a source for one, and during testing two scans of the same prescription
produced different primary interactions. The dataset gives the same answer
every time and it's traceable.

Build it once (~8 MB, gitignored):

```bash
python scripts/import_ddinter.py
```

Without it, the endpoint returns `checked: false` — never an empty result,
which would read as "checked, nothing found".

Three behaviours worth knowing before changing any of it:

- **Unknown drugs are reported, never guessed at.** A name the dataset
  doesn't hold comes back in `unrecognized` and the app marks that medicine
  "Not in safety database" rather than showing the green "No interaction"
  badge. Fuzzy-matching an unfamiliar name onto a similar-looking one is the
  same class of silent wrongness the OCR review gate exists to prevent.
- **DDInter names drugs the US way.** It knows `Acetaminophen`, not
  `Paracetamol`; `Acetylsalicylic acid`, not `Aspirin`. A curated synonym
  table in the import script bridges that plus common Indian brand names —
  without it the single most common drug in the target market would be
  unrecognized. The build warns about any synonym that fails to link; treat
  that warning as a build failure.
- **19% of the table has no established severity.** Those pairs are counted
  in `ungraded_pair_count` and disclosed, but not shown as warnings. On a
  routine five-drug prescription eight of nine pairs came back that way in
  testing; rendering them as alerts would bury the real ones and teach
  patients the alerts mean nothing.

**Licensing — verify before shipping commercially.** DDInter is published by
Xiong et al. (*Nucleic Acids Research*, 2022) and distributed for academic
use. The download endpoints serve no machine-readable licence, so the terms
have **not** been confirmed here. The generated database is gitignored so
nothing redistributes it by accident. Check with the maintainers before any
commercial deployment, and cite the paper.

## Pharmacy search is proxied, and the location is coarsened

`/api/v1/pharmacies/nearby` does the OpenStreetMap lookup on the device's
behalf. The app used to query Overpass directly, which sent a patient's
precise coordinates to a third party on every search.

Before the query leaves, the centre is snapped to a ~550 m grid, so what
Overpass sees is a neighbourhood rather than a doorstep. The search radius
is widened by the cell's reach so nothing genuinely nearby is lost, results
are trimmed back to the radius actually asked for, and distances are
measured from the caller's real position — which never leaves this server.
Accuracy is unchanged; measured against live Overpass, the nearest pharmacy
came back at 494 m from one position and 434 m from another 300 m away, both
from the same cached result set.

Snapping also makes the cache key coarse on purpose: everyone in a
neighbourhood shares one entry, for 24 hours. A repeat search near a warm
cell went from 4.7 s to 8 ms and never touched Overpass. That matters
beyond speed — Overpass is donated infrastructure whose usage policy asks
callers to cache rather than re-query.

Overpass is still contacted, just at arm's length. Eliminating it entirely
means self-hosting an OSM extract, which is a real option and a much larger
one. **Map tiles are a separate matter** and are still fetched directly from
`tile.openstreetmap.org` by the Flutter client, so panning the map reveals
the area being viewed. Proxying tiles is not the fix — OSM's tile usage
policy asks apps with real traffic to run their own tile server or use a
commercial provider.

## Tests

```bash
pytest -q
```

The OCR calibration tests need the Tesseract binary and skip without it.
`test_structuring_live.py` additionally needs the model running and skips
otherwise — it's the only test that performs real inference, and it guards
the field separation in the structuring prompt, which a small local model
gets wrong without the worked examples the prompt carries. Everything else
runs with no model: `app/llm.py` is covered against an in-process stand-in
server.

If you change `_STRUCTURE_SYSTEM_PROMPT`, re-measure on a prescription whose
drugs and notation appear nowhere in its examples. Tuning a prompt against
its own examples looks like a large win and generalises to nothing.
