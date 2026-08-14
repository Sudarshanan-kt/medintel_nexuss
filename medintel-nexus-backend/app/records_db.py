"""Uploads, prescriptions and reports, kept on disk instead of in memory.

These records used to live in module-level dicts. That is fine until the
process stops, and this process stops often: `--reload` restarts it on every
file save. What went with it was not the scanned image — those bytes are on
disk in `uploads/` — but everything derived from them, and the derived half is
the expensive half. A prescription's structured medicines cost an OCR pass and
a local-model round trip to produce, tens of seconds on CPU. Worse, `verified`
went too: a patient who had just read their own prescription line by line and
confirmed an uncertain drug name lost that confirmation to a restart and had
to do it again, which is the one interaction in this app it is least
acceptable to ask twice.

SQLite rather than Postgres for the same reason `interactions_db` uses it —
this backend is a single process serving one household's phone, and a file
that needs no server to be running is the honest fit for that. It is also
already a dependency of the standard library, so it adds nothing to install.

The records here are the *analysis pipeline's* working state, not the
patient's library. Saved reports still live in Supabase, written by the
Flutter client (see the note at the top of `routers/reports.py`).

Writes go through `put_*`, which are whole-record upserts rather than field
patches. Callers mutate a dataclass and hand the whole thing back — the same
shape the in-memory version had, so the pipeline code reads the way it did.
That costs a rewrite of a row that is at most a few kilobytes and buys not
having a partial-update path that can drift from the object.
"""

import json
import logging
import sqlite3
import threading
import time
from contextlib import contextmanager
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterator, List, Optional

logger = logging.getLogger(__name__)

DEFAULT_DB_PATH = Path(__file__).resolve().parent.parent / "data" / "records.sqlite3"

SCHEMA_VERSION = 2

_db_path: Path = DEFAULT_DB_PATH
# Schema setup is per-path and once per path, so pointing tests at a temp file
# doesn't skip the migration that file still needs.
_ready: set[str] = set()
_ready_lock = threading.Lock()


def use(path: Path | str) -> None:
    """Points storage at [path]. Tests call this; the app uses the default.

    Kept as a function rather than a setting because the only caller that
    needs to move it is the test suite, and a test that writes into the real
    `data/records.sqlite3` would leave the developer's own scans behind it.
    """
    global _db_path
    _db_path = Path(path)


def db_path() -> Path:
    return _db_path


# ── Records ──────────────────────────────────────────────────────────────


@dataclass
class UploadRecord:
    id: str
    user_id: str
    file_name: str
    mime_type: str
    size_bytes: int
    signed_url: str
    storage_path: Optional[str] = None


@dataclass
class PrescriptionRecord:
    id: str
    user_id: str
    status: str = "queued"
    ocr_confidence: Optional[float] = None
    medicines: List[dict] = field(default_factory=list)
    created_at: float = field(default_factory=time.time)
    image_path: Optional[str] = None
    # Human-in-the-loop gate. A prescription is only "verified" once either
    # the OCR read every field confidently enough to stand on its own, or
    # the patient confirmed/corrected the uncertain ones. Risk analysis
    # refuses to run against an unverified record — acting on a misread drug
    # name is the worst failure this pipeline has.
    verified: bool = False
    verified_at: Optional[float] = None
    # True when the patient (not the OCR) settled the uncertain fields.
    verified_by_user: bool = False

    @property
    def needs_review(self) -> bool:
        return self.status == "analyzed" and not self.verified

    @property
    def review_field_count(self) -> int:
        """How many fields the review UI should highlight."""
        return sum(len(m.get("low_confidence_fields") or []) for m in self.medicines)

    @property
    def blocking_field_count(self) -> int:
        """How many of those are uncertain enough to hold up risk analysis."""
        return sum(len(m.get("blocking_fields") or []) for m in self.medicines)


@dataclass
class ReportRecord:
    id: str
    user_id: str
    status: str = "queued"
    ocr_confidence: Optional[float] = None
    summary: str = ""
    metrics: List[dict] = field(default_factory=list)
    findings: List[dict] = field(default_factory=list)
    advice: List[dict] = field(default_factory=list)
    created_at: float = field(default_factory=time.time)
    image_path: Optional[str] = None


# ── Connection and schema ────────────────────────────────────────────────

_SCHEMA = """
CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS uploads (
    id           TEXT PRIMARY KEY,
    user_id      TEXT NOT NULL,
    file_name    TEXT NOT NULL,
    mime_type    TEXT NOT NULL,
    size_bytes   INTEGER NOT NULL,
    signed_url   TEXT NOT NULL,
    storage_path TEXT
);

CREATE TABLE IF NOT EXISTS prescriptions (
    id               TEXT PRIMARY KEY,
    user_id          TEXT NOT NULL,
    status           TEXT NOT NULL,
    ocr_confidence   REAL,
    medicines        TEXT NOT NULL DEFAULT '[]',
    created_at       REAL NOT NULL,
    image_path       TEXT,
    verified         INTEGER NOT NULL DEFAULT 0,
    verified_at      REAL,
    verified_by_user INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS reports (
    id             TEXT PRIMARY KEY,
    user_id        TEXT NOT NULL,
    status         TEXT NOT NULL,
    ocr_confidence REAL,
    summary        TEXT NOT NULL DEFAULT '',
    metrics        TEXT NOT NULL DEFAULT '[]',
    findings       TEXT NOT NULL DEFAULT '[]',
    advice         TEXT NOT NULL DEFAULT '[]',
    created_at     REAL NOT NULL,
    image_path     TEXT
);

-- Pharmacy lookups, keyed by the already-snapped grid cell. No user_id
-- column on purpose: the whole point of snapping is that the entry belongs
-- to a neighbourhood rather than a person, and everyone in that cell shares
-- it. Storing who asked would put back the association the coarsening
-- exists to remove.
CREATE TABLE IF NOT EXISTS pharmacy_cache (
    lat        REAL NOT NULL,
    lon        REAL NOT NULL,
    radius_m   INTEGER NOT NULL,
    stored_at  REAL NOT NULL,
    pharmacies TEXT NOT NULL,
    PRIMARY KEY (lat, lon, radius_m)
);

-- Eviction picks the oldest rows, so that ordering is worth an index.
CREATE INDEX IF NOT EXISTS idx_pharmacy_cache_age
    ON pharmacy_cache (stored_at);

-- Every read is either by id (the primary key) or "this user's records,
-- newest first", which is what the client's history screens ask for.
CREATE INDEX IF NOT EXISTS idx_prescriptions_user
    ON prescriptions (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reports_user
    ON reports (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_uploads_user
    ON uploads (user_id);
"""


def _prepare(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(path, timeout=10.0)
    try:
        # WAL so a background OCR task writing a result never blocks the
        # polling GET that is asking whether it finished yet.
        connection.execute("PRAGMA journal_mode = WAL")
        connection.executescript(_SCHEMA)
        connection.execute(
            "INSERT OR REPLACE INTO meta (key, value) VALUES ('schema_version', ?)",
            (str(SCHEMA_VERSION),),
        )
        connection.commit()
    finally:
        connection.close()


@contextmanager
def _db() -> Iterator[sqlite3.Connection]:
    path = _db_path
    key = str(path)
    if key not in _ready:
        with _ready_lock:
            if key not in _ready:
                _prepare(path)
                _ready.add(key)
    # `timeout` is how long a writer waits for another writer's lock before
    # giving up. The default is 5s; OCR results land while the client is
    # polling, so leave room rather than surfacing "database is locked" as a
    # failed scan.
    connection = sqlite3.connect(path, timeout=10.0)
    connection.row_factory = sqlite3.Row
    try:
        # `with connection` commits on a clean exit and rolls back on an
        # exception; it does not close, which is what the finally is for.
        with connection:
            yield connection
    finally:
        connection.close()


# ── Uploads ──────────────────────────────────────────────────────────────


def put_upload(record: UploadRecord) -> UploadRecord:
    with _db() as connection:
        connection.execute(
            """
            INSERT INTO uploads
                (id, user_id, file_name, mime_type, size_bytes, signed_url,
                 storage_path)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                user_id      = excluded.user_id,
                file_name    = excluded.file_name,
                mime_type    = excluded.mime_type,
                size_bytes   = excluded.size_bytes,
                signed_url   = excluded.signed_url,
                storage_path = excluded.storage_path
            """,
            (
                record.id,
                record.user_id,
                record.file_name,
                record.mime_type,
                record.size_bytes,
                record.signed_url,
                record.storage_path,
            ),
        )
    return record


def get_upload(upload_id: str) -> Optional[UploadRecord]:
    with _db() as connection:
        row = connection.execute(
            "SELECT * FROM uploads WHERE id = ?", (upload_id,)
        ).fetchone()
    return None if row is None else _upload_of(row)


def _upload_of(row: sqlite3.Row) -> UploadRecord:
    return UploadRecord(
        id=row["id"],
        user_id=row["user_id"],
        file_name=row["file_name"],
        mime_type=row["mime_type"],
        size_bytes=row["size_bytes"],
        signed_url=row["signed_url"],
        storage_path=row["storage_path"],
    )


# ── Prescriptions ────────────────────────────────────────────────────────


def put_prescription(record: PrescriptionRecord) -> PrescriptionRecord:
    with _db() as connection:
        connection.execute(
            """
            INSERT INTO prescriptions
                (id, user_id, status, ocr_confidence, medicines, created_at,
                 image_path, verified, verified_at, verified_by_user)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                user_id          = excluded.user_id,
                status           = excluded.status,
                ocr_confidence   = excluded.ocr_confidence,
                medicines        = excluded.medicines,
                created_at       = excluded.created_at,
                image_path       = excluded.image_path,
                verified         = excluded.verified,
                verified_at      = excluded.verified_at,
                verified_by_user = excluded.verified_by_user
            """,
            (
                record.id,
                record.user_id,
                record.status,
                record.ocr_confidence,
                json.dumps(record.medicines),
                record.created_at,
                record.image_path,
                int(record.verified),
                record.verified_at,
                int(record.verified_by_user),
            ),
        )
    return record


def get_prescription(prescription_id: str) -> Optional[PrescriptionRecord]:
    with _db() as connection:
        row = connection.execute(
            "SELECT * FROM prescriptions WHERE id = ?", (prescription_id,)
        ).fetchone()
    return None if row is None else _prescription_of(row)


def list_prescriptions(user_id: str, limit: int = 50) -> List[PrescriptionRecord]:
    with _db() as connection:
        rows = connection.execute(
            """
            SELECT * FROM prescriptions
            WHERE user_id = ?
            ORDER BY created_at DESC
            LIMIT ?
            """,
            (user_id, limit),
        ).fetchall()
    return [_prescription_of(row) for row in rows]


def delete_prescription(prescription_id: str) -> None:
    with _db() as connection:
        connection.execute(
            "DELETE FROM prescriptions WHERE id = ?", (prescription_id,)
        )


def _prescription_of(row: sqlite3.Row) -> PrescriptionRecord:
    return PrescriptionRecord(
        id=row["id"],
        user_id=row["user_id"],
        status=row["status"],
        ocr_confidence=row["ocr_confidence"],
        medicines=json.loads(row["medicines"]),
        created_at=row["created_at"],
        image_path=row["image_path"],
        verified=bool(row["verified"]),
        verified_at=row["verified_at"],
        verified_by_user=bool(row["verified_by_user"]),
    )


# ── Reports ──────────────────────────────────────────────────────────────


def put_report(record: ReportRecord) -> ReportRecord:
    with _db() as connection:
        connection.execute(
            """
            INSERT INTO reports
                (id, user_id, status, ocr_confidence, summary, metrics,
                 findings, advice, created_at, image_path)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                user_id        = excluded.user_id,
                status         = excluded.status,
                ocr_confidence = excluded.ocr_confidence,
                summary        = excluded.summary,
                metrics        = excluded.metrics,
                findings       = excluded.findings,
                advice         = excluded.advice,
                created_at     = excluded.created_at,
                image_path     = excluded.image_path
            """,
            (
                record.id,
                record.user_id,
                record.status,
                record.ocr_confidence,
                record.summary,
                json.dumps(record.metrics),
                json.dumps(record.findings),
                json.dumps(record.advice),
                record.created_at,
                record.image_path,
            ),
        )
    return record


def get_report(report_id: str) -> Optional[ReportRecord]:
    with _db() as connection:
        row = connection.execute(
            "SELECT * FROM reports WHERE id = ?", (report_id,)
        ).fetchone()
    return None if row is None else _report_of(row)


def list_reports(user_id: str, limit: int = 50) -> List[ReportRecord]:
    with _db() as connection:
        rows = connection.execute(
            """
            SELECT * FROM reports
            WHERE user_id = ?
            ORDER BY created_at DESC
            LIMIT ?
            """,
            (user_id, limit),
        ).fetchall()
    return [_report_of(row) for row in rows]


def _report_of(row: sqlite3.Row) -> ReportRecord:
    return ReportRecord(
        id=row["id"],
        user_id=row["user_id"],
        status=row["status"],
        ocr_confidence=row["ocr_confidence"],
        summary=row["summary"],
        metrics=json.loads(row["metrics"]),
        findings=json.loads(row["findings"]),
        advice=json.loads(row["advice"]),
        created_at=row["created_at"],
        image_path=row["image_path"],
    )


# ── Pharmacy cache ───────────────────────────────────────────────────────
#
# Storage only. How long an entry stays good and how many are kept are
# decisions about the feature, and they live with it in
# `routers/pharmacies.py` — that module is where the reasoning about Overpass
# being donated infrastructure belongs.


def get_cached_pharmacies(
    lat: float, lon: float, radius_m: int, max_age_seconds: float
) -> Optional[List[dict]]:
    """The stored result for this grid cell, or None if absent or stale.

    [lat] and [lon] must already be snapped by the caller. Matching is exact
    equality on the stored doubles, which holds because snapping is
    deterministic — the same position always produces the same key.
    """
    with _db() as connection:
        row = connection.execute(
            """
            SELECT stored_at, pharmacies FROM pharmacy_cache
            WHERE lat = ? AND lon = ? AND radius_m = ?
            """,
            (lat, lon, radius_m),
        ).fetchone()
    if row is None or time.time() - row["stored_at"] > max_age_seconds:
        return None
    return json.loads(row["pharmacies"])


def put_cached_pharmacies(
    lat: float,
    lon: float,
    radius_m: int,
    pharmacies: List[dict],
    *,
    max_age_seconds: float,
    max_entries: int,
) -> None:
    """Stores a result and takes out the rubbish in the same transaction.

    Expired rows go first, then oldest-first until the table is within
    [max_entries]. Doing it on write rather than on read keeps the hot path —
    a cache hit — to a single indexed SELECT.
    """
    with _db() as connection:
        connection.execute(
            """
            INSERT INTO pharmacy_cache (lat, lon, radius_m, stored_at, pharmacies)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(lat, lon, radius_m) DO UPDATE SET
                stored_at  = excluded.stored_at,
                pharmacies = excluded.pharmacies
            """,
            (lat, lon, radius_m, time.time(), json.dumps(pharmacies)),
        )
        connection.execute(
            "DELETE FROM pharmacy_cache WHERE stored_at < ?",
            (time.time() - max_age_seconds,),
        )
        connection.execute(
            """
            DELETE FROM pharmacy_cache WHERE rowid IN (
                SELECT rowid FROM pharmacy_cache
                ORDER BY stored_at DESC
                LIMIT -1 OFFSET ?
            )
            """,
            (max_entries,),
        )


def clear_pharmacy_cache() -> None:
    with _db() as connection:
        connection.execute("DELETE FROM pharmacy_cache")


def count_cached_pharmacy_cells() -> int:
    with _db() as connection:
        return connection.execute(
            "SELECT COUNT(*) FROM pharmacy_cache"
        ).fetchone()[0]


# ── Startup repair ───────────────────────────────────────────────────────

# Statuses that mean "a background task is working on this". They are only
# true while the process that started that task is alive.
_IN_FLIGHT = ("queued", "processing")


def fail_interrupted_processing() -> int:
    """Marks work the last process was mid-way through as failed.

    A record persists; the asyncio task chewing on it does not. Nothing
    restarts it, so a row left saying "processing" is a client polling a
    status that will never change — a scan that appears to hang forever
    rather than fail. In-memory storage hid this by losing the record
    outright, which at least produced a 404.

    Failing them is honest and recoverable: the uploaded image is still on
    disk, `failed` is a state the client already renders, and the offer it
    renders alongside it is Try again, which calls `/reprocess` and runs the
    pipeline over that same image. The alternative — re-queueing everything
    automatically on boot — starts an unbounded number of OCR and local-model
    jobs at the least convenient moment, for results nobody may be waiting on.

    Returns how many rows were reset, for the startup log.
    """
    placeholders = ", ".join("?" for _ in _IN_FLIGHT)
    with _db() as connection:
        changed = 0
        for table in ("prescriptions", "reports"):
            cursor = connection.execute(
                f"UPDATE {table} SET status = 'failed' "  # noqa: S608 — fixed literals
                f"WHERE status IN ({placeholders})",
                _IN_FLIGHT,
            )
            changed += cursor.rowcount
    return changed
