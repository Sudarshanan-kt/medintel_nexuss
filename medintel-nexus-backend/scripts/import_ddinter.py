"""Builds the local drug-interaction database from DDInter 2.0.

    python scripts/import_ddinter.py            # download, then build
    python scripts/import_ddinter.py --from-dir ./downloads

Produces `data/interactions.sqlite3`, which is gitignored: it is derived
third-party data, not source. Anyone setting the project up runs this once.

LICENSING — read before shipping this in a product. DDInter is published by
the Xiong et al. group (Nucleic Acids Research, 2022) and distributed for
academic use. The download endpoints serve no machine-readable licence, so
the terms have NOT been verified here. Confirm them with the maintainers
before any commercial deployment, and cite the paper in anything published.
"""

import argparse
import csv
import sqlite3
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.interactions_db import _LEVEL_RANK, DB_PATH, LEVELS, normalize  # noqa: E402

SOURCE = "DDInter 2.0"
BASE_URL = "http://ddinter.scbdd.com/static/media/download"

# DDInter splits its data by the first level of the ATC classification.
ATC_CODES = ["A", "B", "D", "G", "H", "J", "L", "M", "N", "P", "R", "S", "V"]

# Names the dataset doesn't carry, mapped onto the one it does. Every entry
# is a claim that two names are the same drug; a wrong one would silently
# apply a different drug's interaction profile, so these are hand-checked
# and the build warns loudly about any that fail to link. Grow it from real
# misses reported by /interactions/check, never by bulk import.
#
# Two groups, and the first is the important one:
#
# 1. DDInter names drugs the US way. Prescriptions in India, the UK and
#    most of the WHO's INN world do not. "Paracetamol" is on nearly every
#    prescription this app will ever see and the dataset only knows it as
#    "Acetaminophen" — without this mapping the most common drug in the
#    target market comes back unrecognized. Note the dataset is not
#    consistent about it: it holds Salbutamol and Rifampicin under their INN
#    names while using Epinephrine and Furosemide for others, so each pair
#    below was checked against the built database rather than assumed.
#
# 2. Brand names common on Indian prescriptions.
SYNONYMS = {
    # INN / British -> the US name DDInter uses
    "paracetamol": "Acetaminophen",
    "aspirin": "Acetylsalicylic acid",
    "adrenaline": "Epinephrine",
    "noradrenaline": "Norepinephrine",
    "lignocaine": "Lidocaine",
    "frusemide": "Furosemide",
    "pethidine": "Meperidine",
    "glyceryl trinitrate": "Nitroglycerin",
    "gtn": "Nitroglycerin",
    "thyroxine": "Levothyroxine",
    "cyclosporin": "Cyclosporine",
    "amoxycillin": "Amoxicillin",  # common alternate spelling
    # Brands
    "crocin": "Acetaminophen",
    "calpol": "Acetaminophen",
    "dolo": "Acetaminophen",
    "tylenol": "Acetaminophen",
    "ecosprin": "Acetylsalicylic acid",
    "disprin": "Acetylsalicylic acid",
    "brufen": "Ibuprofen",
    "combiflam": "Ibuprofen",
    "lipitor": "Atorvastatin",
    "glucophage": "Metformin",
    "glycomet": "Metformin",
    "nexium": "Esomeprazole",
    "pantocid": "Pantoprazole",
    "omez": "Omeprazole",
    "augmentin": "Amoxicillin",
    "amoxil": "Amoxicillin",
    "voveran": "Diclofenac",
    "zocor": "Simvastatin",
    "coumadin": "Warfarin",
    "amlong": "Amlodipine",
    "lasix": "Furosemide",
    "zithromax": "Azithromycin",
}

SCHEMA = """
CREATE TABLE drugs (
    id          INTEGER PRIMARY KEY,
    name        TEXT NOT NULL,
    normalized  TEXT NOT NULL UNIQUE
);
CREATE TABLE interactions (
    drug_a  INTEGER NOT NULL,
    drug_b  INTEGER NOT NULL,
    level   TEXT NOT NULL,
    PRIMARY KEY (drug_a, drug_b)
);
CREATE TABLE synonyms (
    normalized  TEXT PRIMARY KEY,
    drug_id     INTEGER NOT NULL REFERENCES drugs(id)
);
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
CREATE INDEX idx_drugs_normalized ON drugs(normalized);
"""


def download(target: Path) -> Path:
    target.mkdir(parents=True, exist_ok=True)
    for code in ATC_CODES:
        path = target / f"ddinter_{code}.csv"
        if path.exists() and path.stat().st_size > 0:
            print(f"  {code}: cached")
            continue
        url = f"{BASE_URL}/ddinter_downloads_code_{code}.csv"
        print(f"  {code}: downloading…", flush=True)
        urllib.request.urlopen(url, timeout=120)  # fail fast on a bad URL
        urllib.request.urlretrieve(url, path)
    return target


def read_pairs(source_dir: Path):
    """Yields (drug_a, drug_b, level), skipping malformed and self-pairs."""
    for path in sorted(source_dir.glob("ddinter_*.csv")):
        with path.open(newline="", encoding="utf-8") as handle:
            for row in csv.DictReader(handle):
                a = (row.get("Drug_A") or "").strip()
                b = (row.get("Drug_B") or "").strip()
                level = (row.get("Level") or "").strip()
                if not a or not b or level not in LEVELS:
                    continue
                if normalize(a) == normalize(b):
                    continue
                yield a, b, level


def build(source_dir: Path, db_path: Path) -> None:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    if db_path.exists():
        db_path.unlink()

    connection = sqlite3.connect(db_path)
    connection.executescript(SCHEMA)

    drug_ids: dict = {}
    names: dict = {}

    def drug_id(name: str) -> int:
        key = normalize(name)
        if key not in drug_ids:
            drug_ids[key] = len(drug_ids) + 1
            names[key] = name
        return drug_ids[key]

    # A pair can appear in several ATC files, sometimes graded differently.
    # Keep the most severe grading rather than whichever file was read last.
    pairs: dict = {}
    skipped = 0
    for a, b, level in read_pairs(source_dir):
        id_a, id_b = drug_id(a), drug_id(b)
        key = (min(id_a, id_b), max(id_a, id_b))
        existing = pairs.get(key)
        if existing is None or _LEVEL_RANK[level] > _LEVEL_RANK[existing]:
            if existing is not None:
                skipped += 1
            pairs[key] = level
        else:
            skipped += 1

    connection.executemany(
        "INSERT INTO drugs (id, name, normalized) VALUES (?, ?, ?)",
        [(i, names[k], k) for k, i in drug_ids.items()],
    )
    connection.executemany(
        "INSERT INTO interactions (drug_a, drug_b, level) VALUES (?, ?, ?)",
        [(a, b, level) for (a, b), level in pairs.items()],
    )

    linked = 0
    missing = []
    for alias, generic in SYNONYMS.items():
        key = normalize(generic)
        target = drug_ids.get(key)
        if target is None:
            missing.append(f"{alias} -> {generic}")
            continue
        connection.execute(
            "INSERT OR REPLACE INTO synonyms (normalized, drug_id) VALUES (?, ?)",
            (normalize(alias), target),
        )
        linked += 1

    connection.executemany(
        "INSERT INTO meta (key, value) VALUES (?, ?)",
        [
            ("source", SOURCE),
            ("drug_count", str(len(drug_ids))),
            ("interaction_count", str(len(pairs))),
            ("synonym_count", str(linked)),
        ],
    )
    connection.commit()
    connection.close()

    print(f"\n  drugs        : {len(drug_ids):,}")
    print(f"  interactions : {len(pairs):,}  ({skipped:,} duplicate rows merged)")
    print(f"  synonyms     : {linked}")
    if missing:
        print(f"  \033[33munlinked synonyms: {', '.join(missing)}\033[0m")
    print(f"\n  wrote {db_path} ({db_path.stat().st_size / 1_048_576:.1f} MB)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--from-dir",
        type=Path,
        help="Use CSVs already on disk instead of downloading them.",
    )
    parser.add_argument("--out", type=Path, default=DB_PATH)
    args = parser.parse_args()

    source = args.from_dir
    if source is None:
        source = download(Path(__file__).resolve().parent.parent / "data" / "ddinter")
    print(f"Building from {source}")
    build(source, args.out)


if __name__ == "__main__":
    main()
