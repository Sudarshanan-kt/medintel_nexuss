"""The local interaction dataset: name resolution and lookup.

Built against a small purpose-made database rather than the real DDInter
import, so these run anywhere and don't drift when the dataset is rebuilt.
"""

import sqlite3

import pytest

from app import interactions_db


@pytest.fixture
def dataset(tmp_path, monkeypatch):
    """A miniature stand-in with the same schema as the real import."""
    path = tmp_path / "interactions.sqlite3"
    connection = sqlite3.connect(path)
    connection.executescript(
        """
        CREATE TABLE drugs (id INTEGER PRIMARY KEY, name TEXT, normalized TEXT UNIQUE);
        CREATE TABLE interactions (drug_a INTEGER, drug_b INTEGER, level TEXT,
                                   PRIMARY KEY (drug_a, drug_b));
        CREATE TABLE synonyms (normalized TEXT PRIMARY KEY, drug_id INTEGER);
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
        """
    )
    connection.executemany(
        "INSERT INTO drugs VALUES (?, ?, ?)",
        [
            (1, "Warfarin", "warfarin"),
            (2, "Acetylsalicylic acid", "acetylsalicylic acid"),
            (3, "Acetaminophen", "acetaminophen"),
            (4, "Amoxicillin", "amoxicillin"),
        ],
    )
    connection.executemany(
        "INSERT INTO interactions VALUES (?, ?, ?)",
        [
            (1, 2, "Major"),
            (1, 3, "Moderate"),
            (2, 3, "Minor"),
            (3, 4, "Unknown"),
        ],
    )
    connection.executemany(
        "INSERT INTO synonyms VALUES (?, ?)",
        [("aspirin", 2), ("paracetamol", 3), ("crocin", 3)],
    )
    connection.executemany(
        "INSERT INTO meta VALUES (?, ?)", [("source", "test-fixture")]
    )
    connection.commit()
    connection.close()

    monkeypatch.setattr(interactions_db, "DB_PATH", path)
    return path


class TestNormalize:
    def test_strips_the_dosage_form_prefix(self):
        assert interactions_db.normalize("Tab Amoxicillin") == "amoxicillin"
        assert interactions_db.normalize("Cap. Omeprazole") == "omeprazole"
        assert interactions_db.normalize("Syp Lactulose") == "lactulose"

    def test_strips_the_strength(self):
        assert interactions_db.normalize("Amoxicillin 500mg") == "amoxicillin"
        assert interactions_db.normalize("Lactulose 15 ml") == "lactulose"

    def test_strips_a_line_enumerator(self):
        assert interactions_db.normalize("1. Tab Warfarin 5mg") == "warfarin"

    def test_keeps_multi_word_drug_names_intact(self):
        """"Sodium chloride" is one drug; only a LEADING form word goes."""
        assert (
            interactions_db.normalize("Sodium chloride") == "sodium chloride"
        )
        assert (
            interactions_db.normalize("Acetylsalicylic acid")
            == "acetylsalicylic acid"
        )

    def test_is_case_and_punctuation_insensitive(self):
        assert interactions_db.normalize("  WARFARIN.  ") == "warfarin"


class TestLookup:
    def test_finds_a_major_interaction(self, dataset):
        result = interactions_db.check(["Warfarin", "Acetylsalicylic acid"])

        assert result.overall_risk == "severe"
        assert result.interactions[0].level == "Major"
        assert result.interactions[0].risk == "severe"

    def test_resolves_a_synonym_to_the_dataset_drug(self, dataset):
        """A prescription says "Paracetamol"; DDInter only knows
        "Acetaminophen". Without this the commonest drug in the target
        market would come back unrecognized."""
        result = interactions_db.check(["Paracetamol", "Warfarin"])

        assert result.unrecognized == []
        assert result.interactions[0].level == "Moderate"

    def test_reports_the_callers_own_name_not_the_datasets(self, dataset):
        """The caller has to match the verdict back to a medicine on screen,
        and "Aspirin" never matches "Acetylsalicylic acid"."""
        result = interactions_db.check(["Aspirin", "Warfarin"])

        assert set(result.interactions[0].pair) == {"Aspirin", "Warfarin"}
        assert set(result.interactions[0].canonical_pair) == {
            "Acetylsalicylic acid",
            "Warfarin",
        }

    def test_an_unknown_drug_is_reported_never_guessed_at(self, dataset):
        result = interactions_db.check(["Warfarin", "Zorbtive9000"])

        assert result.unrecognized == ["Zorbtive9000"]
        assert result.interactions == []
        # The caller must be able to tell this apart from a clean result.
        assert result.overall_risk == "none"

    def test_a_near_miss_is_not_fuzzy_matched_onto_a_real_drug(self, dataset):
        """"Warfarin" and "Warfarine" look alike. Guessing which drug a
        patient is on is the failure mode this whole feature avoids."""
        result = interactions_db.check(["Warfarine", "Aspirin"])

        assert "Warfarine" in result.unrecognized

    def test_an_ungraded_pair_is_separated_from_real_warnings(self, dataset):
        """19% of the real table has no established severity. Showing those
        as warnings buries the graded ones."""
        result = interactions_db.check(["Acetaminophen", "Amoxicillin"])

        assert result.interactions == []
        assert len(result.ungraded) == 1
        assert result.ungraded[0].level == "Unknown"
        assert result.overall_risk == "none"

    def test_the_most_severe_pair_drives_the_overall_risk(self, dataset):
        result = interactions_db.check(
            ["Warfarin", "Aspirin", "Paracetamol"]
        )

        assert len(result.interactions) == 3
        assert result.overall_risk == "severe"
        # Sorted worst-first so the UI leads with what matters.
        assert result.interactions[0].level == "Major"

    def test_the_same_query_always_gives_the_same_answer(self, dataset):
        """The property an LLM could not provide, and the reason this
        dataset exists."""
        names = ["Warfarin", "Aspirin", "Paracetamol"]
        runs = [
            [(i.level, tuple(sorted(i.pair))) for i in interactions_db.check(names).interactions]
            for _ in range(5)
        ]

        assert all(run == runs[0] for run in runs)

    def test_a_missing_dataset_reports_nothing_rather_than_safety(
        self, tmp_path, monkeypatch
    ):
        """None means "could not check". An empty result would be read as
        "checked, nothing found"."""
        monkeypatch.setattr(interactions_db, "DB_PATH", tmp_path / "absent.sqlite3")

        assert interactions_db.is_available() is False
        assert interactions_db.check(["Warfarin", "Aspirin"]) is None
