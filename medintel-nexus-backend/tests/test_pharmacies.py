"""The pharmacy proxy, and the coarsening that is its whole point.

If the snapped coordinates were ever wrong — too fine to anonymise, or
coarse enough to lose nearby results — the feature would either leak the
patient's position or quietly return the wrong shops. Both are tested here.
"""

import urllib.parse

import httpx
import pytest
from fastapi.testclient import TestClient

from app import records_db
from app.config import settings
from app.routers import pharmacies
from main import app

client = TestClient(app)
AUTH = {"Authorization": "Bearer dev"}

# A precise position — a doorstep, to four decimal places.
EXACT_LAT, EXACT_LON = 13.08268, 80.27072


@pytest.fixture(autouse=True)
def dev_auth(monkeypatch):
    monkeypatch.setattr(settings, "auth_disabled", True)
    # The cache outlives the process now, so it also outlives a test unless
    # it is cleared — a hit left by an earlier test would mean the next one
    # never reaches its stand-in Overpass at all. conftest already points
    # storage at a temp file, so this only empties that.
    records_db.clear_pharmacy_cache()


@pytest.fixture
def overpass(monkeypatch):
    """Stands in for Overpass and records exactly what it was sent.

    Records the Overpass query itself rather than the raw body, so these
    tests assert on what was asked for and not on how it happened to be
    form-encoded on the wire.
    """
    seen = []

    def install(elements, fail=False, fail_first=0):
        def handler(request: httpx.Request) -> httpx.Response:
            body = urllib.parse.parse_qs(request.content.decode())
            seen.append(body["data"][0])
            # `fail_first` models the common case: Overpass is overloaded for
            # the first attempt or two, then answers.
            if fail or len(seen) <= fail_first:
                return httpx.Response(504)
            return httpx.Response(200, json={"elements": elements})

        original = httpx.AsyncClient

        def factory(*args, **kwargs):
            kwargs["transport"] = httpx.MockTransport(handler)
            return original(*args, **kwargs)

        monkeypatch.setattr(httpx, "AsyncClient", factory)
        return seen

    return install


def _node(name, lat, lon, **tags):
    return {"lat": lat, "lon": lon, "tags": {"name": name, **tags}}


class TestCoarsening:
    def test_the_exact_position_is_never_sent_onward(self, overpass):
        seen = overpass([])

        client.get(
            "/api/v1/pharmacies/nearby",
            params={"lat": EXACT_LAT, "lon": EXACT_LON},
            headers=AUTH,
        )

        sent = seen[0]
        assert str(EXACT_LAT) not in sent
        assert str(EXACT_LON) not in sent

    def test_the_snapped_centre_stays_within_the_grid_cell(self):
        """Coarse enough to anonymise, close enough not to move the search
        somewhere else entirely."""
        for value in (13.08268, 80.27072, -0.0001, 51.5074):
            offset = abs(pharmacies._snap(value) - value)
            assert offset <= pharmacies._GRID_DEGREES / 2 + 1e-9

    def test_neighbours_share_one_cache_entry(self, overpass):
        """Two people a few hundred metres apart must look identical to
        Overpass, and cost it one lookup between them."""
        seen = overpass([])

        for lat, lon in ((13.0826, 80.2707), (13.0830, 80.2710)):
            client.get(
                "/api/v1/pharmacies/nearby",
                params={"lat": lat, "lon": lon},
                headers=AUTH,
            )

        # Identical: neither position is recoverable from what was asked.
        assert len(set(seen)) == 1
        # One lookup, not two — the second position came out of the cache.
        # A lookup asks every mirror at once, so it is one query per mirror
        # rather than one query, which is the load racing them costs.
        assert len(seen) == len(pharmacies._ENDPOINTS)

    def test_the_radius_is_widened_to_cover_the_snapping(self, overpass):
        """Snapping moves the centre, so the query has to reach further or a
        pharmacy that was genuinely in range could be missed."""
        seen = overpass([])

        client.get(
            "/api/v1/pharmacies/nearby",
            params={"lat": EXACT_LAT, "lon": EXACT_LON, "radius_m": 3000},
            headers=AUTH,
        )

        assert f"around:{3000 + pharmacies._GRID_SLACK_METRES}" in seen[0]


class TestResults:
    def test_distances_are_measured_from_the_real_position(self, overpass):
        """The coarsening must not degrade what the patient sees. This
        pharmacy is ~100 m away; from the snapped centre it would not be."""
        overpass([_node("Apollo Pharmacy", 13.0836, 80.2707)])

        res = client.get(
            "/api/v1/pharmacies/nearby",
            params={"lat": EXACT_LAT, "lon": EXACT_LON},
            headers=AUTH,
        )

        pharmacy = res.json()["data"]["pharmacies"][0]
        assert pharmacy["distance_m"] < 150

    def test_results_are_sorted_nearest_first(self, overpass):
        overpass(
            [
                _node("Far", 13.1000, 80.2707),
                _node("Near", 13.0830, 80.2707),
                _node("Middle", 13.0900, 80.2707),
            ]
        )

        res = client.get(
            "/api/v1/pharmacies/nearby",
            params={"lat": EXACT_LAT, "lon": EXACT_LON, "radius_m": 20000},
            headers=AUTH,
        )

        names = [p["name"] for p in res.json()["data"]["pharmacies"]]
        assert names == ["Near", "Middle", "Far"]

    def test_the_widened_search_does_not_leak_into_the_results(self, overpass):
        """The radius was widened for snapping; a shop outside what the
        caller actually asked for must still be trimmed."""
        overpass([_node("Just outside", 13.1200, 80.2707)])  # ~4 km away

        res = client.get(
            "/api/v1/pharmacies/nearby",
            params={"lat": EXACT_LAT, "lon": EXACT_LON, "radius_m": 3000},
            headers=AUTH,
        )

        assert res.json()["data"]["pharmacies"] == []

    def test_unnamed_shops_are_dropped(self, overpass):
        """An unnamed node is useless to someone trying to find a shop."""
        overpass([{"lat": 13.083, "lon": 80.271, "tags": {}}])

        res = client.get(
            "/api/v1/pharmacies/nearby",
            params={"lat": EXACT_LAT, "lon": EXACT_LON},
            headers=AUTH,
        )

        assert res.json()["data"]["pharmacies"] == []

    def test_a_way_reports_its_centre_point(self, overpass):
        """Overpass returns areas as `center` rather than lat/lon."""
        overpass(
            [{"center": {"lat": 13.083, "lon": 80.271}, "tags": {"name": "Med Plus"}}]
        )

        res = client.get(
            "/api/v1/pharmacies/nearby",
            params={"lat": EXACT_LAT, "lon": EXACT_LON},
            headers=AUTH,
        )

        assert res.json()["data"]["pharmacies"][0]["name"] == "Med Plus"


class TestFailure:
    def test_an_outage_is_reported_not_shown_as_no_pharmacies(self, overpass):
        """"We couldn't search" and "there are none near you" are different
        things to tell someone looking for a shop."""
        overpass([], fail=True)

        res = client.get(
            "/api/v1/pharmacies/nearby",
            params={"lat": EXACT_LAT, "lon": EXACT_LON},
            headers=AUTH,
        )

        data = res.json()["data"]
        assert data["searched"] is False
        assert data["pharmacies"] == []

    def test_a_busy_mirror_is_tried_again_rather_than_failing_the_search(
        self, overpass
    ):
        """A 504 means Overpass was too busy this second, not that there are
        no pharmacies nearby.

        Giving up on the first one is what made this feature look broken:
        the mirrors return 504 often, and the user got "search unavailable"
        for a query that succeeds on the very next attempt.
        """
        overpass([_node("Apollo Pharmacy", 13.0836, 80.2707)], fail_first=1)

        res = client.get(
            "/api/v1/pharmacies/nearby",
            params={"lat": EXACT_LAT, "lon": EXACT_LON},
            headers=AUTH,
        )

        data = res.json()["data"]
        assert data["searched"] is True
        assert [p["name"] for p in data["pharmacies"]] == ["Apollo Pharmacy"]

    def test_a_failed_search_is_not_cached(self, overpass):
        """Caching an outage would keep the feature broken for a day."""
        seen = overpass([], fail=True)

        def search():
            client.get(
                "/api/v1/pharmacies/nearby",
                params={"lat": EXACT_LAT, "lon": EXACT_LON},
                headers=AUTH,
            )

        search()
        after_first = len(seen)
        assert after_first > 0

        search()

        # The second search queried again rather than being served a cached
        # outage. Expressed as "it tried again", not as a fixed count, so
        # changing how many mirrors or retries a search uses doesn't break
        # the thing actually being tested.
        assert len(seen) == after_first * 2

    def test_nonsense_coordinates_are_rejected(self):
        res = client.get(
            "/api/v1/pharmacies/nearby",
            params={"lat": 200, "lon": 80},
            headers=AUTH,
        )

        assert res.status_code == 422
