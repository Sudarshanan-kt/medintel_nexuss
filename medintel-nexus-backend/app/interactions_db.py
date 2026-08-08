"""Drug-drug interactions, answered from a local dataset rather than a model.

An interaction verdict is a clinical claim. A language model cannot cite a
source for one, and two runs over the same prescription produced different
primary interactions during testing — that non-determinism is disqualifying
for a safety check. This module answers from DDInter 2.0: a fixed pairwise
table with a graded severity per pair, so the same two drugs always get the
same answer and that answer is traceable to a citable source.

The dataset is not committed. Build it with `scripts/import_ddinter.py`;
`app/routers/interactions.py` degrades explicitly when it's absent rather
than falling back to a guess.

What this deliberately does NOT do is guess at names. A drug the dataset
doesn't know comes back in `unrecognized` and the caller has to say so —
fuzzy-matching an unfamiliar name onto a similar-looking one would be the
same class of silent wrongness the OCR review gate exists to prevent.
"""

import logging
import re
import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

logger = logging.getLogger(__name__)

DB_PATH = Path(__file__).resolve().parent.parent / "data" / "interactions.sqlite3"

# DDInter's own grading, kept verbatim so a verdict can be traced back.
LEVELS = ("Major", "Moderate", "Minor", "Unknown")

# Ordering used when the same pair appears in several ATC category files.
# A stated severity always beats "Unknown"; among stated ones, the most
# severe wins. Under-reporting a major interaction is the costly direction.
_LEVEL_RANK = {"Unknown": 0, "Minor": 1, "Moderate": 2, "Major": 3}

# The app's three-level risk vocabulary, which drives the badge colour.
#
# Minor maps to "moderate" rather than "none" on purpose: DDInter recording
# a Minor interaction still means these two drugs interact, and showing that
# as no-risk-at-all would be wrong. The verbatim grading rides along in
# `level` so the text can say "Minor" while the badge stays cautious.
_RISK_BY_LEVEL = {
    "Major": "severe",
    "Moderate": "moderate",
    "Minor": "moderate",
}

# "Unknown" means the pair appears in the dataset with no severity
# established — not that it is dangerous. It is 19% of the table, and on a
# routine five-drug prescription eight of the nine pairs came back this way
# during testing. Rendering those as warnings would put nine amber alerts on
# an ordinary prescription and teach patients that the alerts mean nothing,
# which is a worse safety outcome than not showing them. They are counted
# and disclosed instead of either warned about or silently dropped.
UNGRADED = "Unknown"


def is_graded(level: str) -> bool:
    return level in _RISK_BY_LEVEL

# Dosage form words that prefix a drug name on a prescription line.
_FORM_WORDS = frozenset(
    {
        "tab", "tabs", "tablet", "tablets",
        "cap", "caps", "capsule", "capsules",
        "syp", "syrup", "susp", "suspension",
        "inj", "injection", "amp", "ampoule", "vial",
        "oint", "ointment", "cream", "gel", "lotion",
        "drop", "drops", "soln", "solution", "spray", "sachet",
    }
)

_STRENGTH = re.compile(
    r"\b\d+(?:\.\d+)?\s*(?:mg|mcg|g|gm|ml|l|iu|units?|%)\b", re.IGNORECASE
)
_PARENTHETICAL = re.compile(r"\([^)]*\)")
_NON_WORD = re.compile(r"[^a-z0-9]+")


def normalize(name: str) -> str:
    """Lookup key for a drug name.

    Must behave identically at import time and query time or nothing
    matches, so both paths call this one function.
    """
    text = (name or "").lower()
    text = _PARENTHETICAL.sub(" ", text)
    text = _STRENGTH.sub(" ", text)
    text = _NON_WORD.sub(" ", text)

    words = [w for w in text.split() if w]
    # Strip leading packaging noise: the line enumerator and the dosage
    # form, in whatever order they appear — a real line reads "1. Tab
    # Warfarin 5mg", so removing form words first would leave "tab" behind
    # once the enumerator went.
    #
    # Only LEADING words go. "Sodium chloride" is one drug, and a trailing
    # word is part of the name rather than packaging.
    while words and (words[0] in _FORM_WORDS or words[0].isdigit()):
        words.pop(0)

    return " ".join(words)


@dataclass
class Interaction:
    """One pair the dataset knows about.

    Both namings are kept because they serve different consumers. The
    dataset's canonical name is what the entry is really about and what an
    explanation should be written against; the caller's name is what the
    patient has on their prescription and sees on screen. Reporting only
    the canonical one silently breaks the caller's ability to match the
    result back to a medicine — "Aspirin" never matches
    "Acetylsalicylic acid".
    """

    drug_a: str  # as the caller supplied it
    drug_b: str
    canonical_a: str  # as the dataset names it
    canonical_b: str
    level: str

    @property
    def risk(self) -> str:
        return _RISK_BY_LEVEL.get(self.level, "moderate")

    @property
    def pair(self) -> List[str]:
        return [self.drug_a, self.drug_b]

    @property
    def canonical_pair(self) -> List[str]:
        return [self.canonical_a, self.canonical_b]


@dataclass
class LookupResult:
    """Outcome of checking a set of medicines against the dataset.

    Two fields here must not be dropped on the floor by callers, because
    both change what an empty [interactions] list means:

    [unrecognized] — drugs the dataset has never heard of. Nothing was
    checked for those, so "no interactions found" says nothing about them.

    [ungraded] — pairs the dataset lists without an established severity.
    Not shown as warnings (see [UNGRADED]) but disclosed, so "we found
    nothing" is never quietly standing in for "we found things we couldn't
    grade".
    """

    interactions: List[Interaction]
    ungraded: List[Interaction]
    recognized: Dict[str, str]  # what the caller sent -> dataset drug name
    unrecognized: List[str]

    @property
    def overall_risk(self) -> str:
        if any(i.risk == "severe" for i in self.interactions):
            return "severe"
        if self.interactions:
            return "moderate"
        return "none"


def is_available() -> bool:
    return DB_PATH.exists()


def _connect() -> sqlite3.Connection:
    connection = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    return connection


def metadata() -> Dict[str, str]:
    """Provenance for the loaded dataset — source, version, row counts."""
    if not is_available():
        return {}
    try:
        with _connect() as connection:
            return {
                row["key"]: row["value"]
                for row in connection.execute("SELECT key, value FROM meta")
            }
    except sqlite3.Error:
        logger.exception("Could not read interaction dataset metadata")
        return {}


def _resolve(
    connection: sqlite3.Connection, names: Sequence[str]
) -> Tuple[Dict[str, Tuple[int, str]], List[str]]:
    """Maps each caller-supplied name onto a dataset drug, exactly.

    Exact-after-normalization only. A brand name reaches the dataset through
    the curated `synonyms` table or not at all; it is never guessed at.
    """
    resolved: Dict[str, Tuple[int, str]] = {}
    unrecognized: List[str] = []

    for name in names:
        key = normalize(name)
        if not key:
            unrecognized.append(name)
            continue

        row = connection.execute(
            "SELECT id, name FROM drugs WHERE normalized = ?", (key,)
        ).fetchone()
        if row is None:
            row = connection.execute(
                "SELECT d.id AS id, d.name AS name FROM synonyms s "
                "JOIN drugs d ON d.id = s.drug_id WHERE s.normalized = ?",
                (key,),
            ).fetchone()

        if row is None:
            unrecognized.append(name)
        else:
            resolved[name] = (row["id"], row["name"])

    return resolved, unrecognized


def check(names: Sequence[str]) -> Optional[LookupResult]:
    """Every known interaction among [names].

    Returns None only when the dataset itself is missing or unreadable —
    which callers must report as "the check could not run", never as a
    clean result.
    """
    if not is_available():
        return None

    try:
        with _connect() as connection:
            resolved, unrecognized = _resolve(connection, names)

            graded: List[Interaction] = []
            ungraded: List[Interaction] = []
            entries = list(resolved.items())
            for i in range(len(entries)):
                for j in range(i + 1, len(entries)):
                    (input_a, (id_a, display_a)) = entries[i]
                    (input_b, (id_b, display_b)) = entries[j]
                    low, high = min(id_a, id_b), max(id_a, id_b)
                    row = connection.execute(
                        "SELECT level FROM interactions "
                        "WHERE drug_a = ? AND drug_b = ?",
                        (low, high),
                    ).fetchone()
                    if row is None:
                        continue
                    found = Interaction(
                        drug_a=input_a,
                        drug_b=input_b,
                        canonical_a=display_a,
                        canonical_b=display_b,
                        level=row["level"],
                    )
                    (graded if is_graded(found.level) else ungraded).append(found)

            graded.sort(key=lambda x: -_LEVEL_RANK.get(x.level, 0))
            return LookupResult(
                interactions=graded,
                ungraded=ungraded,
                recognized={k: v[1] for k, v in resolved.items()},
                unrecognized=unrecognized,
            )
    except sqlite3.Error:
        logger.exception("Interaction dataset lookup failed")
        return None
