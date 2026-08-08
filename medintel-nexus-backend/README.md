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
uvicorn main:app --reload --port 8000
```

Check both halves are up:

```bash
curl localhost:8000/health       # the API
curl localhost:8000/health/llm   # the model — says what's wrong if it isn't
```

`/health/llm` exists because every LLM-backed feature degrades quietly by
design. A scan that comes back "couldn't read this" looks identical whether
the photo was bad or `ollama serve` isn't running; this tells you which.

On a USB-connected phone, `adb reverse tcp:8000 tcp:8000` lets the app reach
this backend over the cable.

## Configuration

Copy the settings you need into `.env` (gitignored). Every one has a working
default except the Supabase secret.

| Setting | Default | Notes |
|---|---|---|
| `SUPABASE_JWT_SECRET` | — | Required unless `AUTH_DISABLED=true` |
| `AUTH_DISABLED` | `false` | Dev only. Treats every caller as `dev-user` |
| `LLM_BASE_URL` | `http://localhost:11434/v1` | Any OpenAI-compatible local server |
| `LLM_MODEL` | `qwen2.5:7b-instruct` | Must be pulled first |
| `LLM_API_KEY` | — | Ollama needs none; llama.cpp / LM Studio may |
| `LLM_TIMEOUT_SECONDS` | `180` | A 7B model on CPU is slow; don't cut this short |

Swapping to llama.cpp or LM Studio is a `LLM_BASE_URL` change and nothing
else — `app/llm.py` speaks the shape all of them implement.

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
