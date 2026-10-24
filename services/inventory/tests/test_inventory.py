import pytest
from fastapi.testclient import TestClient

from app.main import app, store


@pytest.fixture(autouse=True)
def fresh_store():
    store.reset()
    yield


@pytest.fixture
def client():
    return TestClient(app)


def test_health(client):
    assert client.get("/health/live").json() == {"status": "alive"}
    body = client.get("/health/ready").json()
    assert body["status"] == "ready"
    assert body["service"] == "inventory"


def test_list_and_get_stock(client):
    skus = [i["sku"] for i in client.get("/stock").json()]
    assert skus[0] == "WMT-1001" and len(skus) == 8
    item = client.get("/stock/WMT-1001").json()
    assert item["available"] == item["on_hand"] == 500
    assert client.get("/stock/NOPE").status_code == 404


def test_reserve_reduces_availability(client):
    r = client.post("/stock/WMT-1001/reserve", json={"quantity": 4})
    assert r.status_code == 200
    assert r.json()["reserved"] == 4
    assert r.json()["available"] == 496


def test_reserve_insufficient_stock_is_409_and_changes_nothing(client):
    r = client.post("/stock/WMT-1008/reserve", json={"quantity": 41})
    assert r.status_code == 409
    assert client.get("/stock/WMT-1008").json()["reserved"] == 0


def test_reserve_unknown_sku_is_404(client):
    assert client.post("/stock/NOPE/reserve", json={"quantity": 1}).status_code == 404


def test_release_returns_stock(client):
    client.post("/stock/WMT-1002/reserve", json={"quantity": 5})
    r = client.post("/stock/WMT-1002/release", json={"quantity": 3})
    assert r.status_code == 200
    assert r.json()["reserved"] == 2


def test_cannot_release_more_than_reserved(client):
    client.post("/stock/WMT-1002/reserve", json={"quantity": 1})
    assert client.post("/stock/WMT-1002/release", json={"quantity": 2}).status_code == 409
    assert client.post("/stock/NOPE/release", json={"quantity": 1}).status_code == 404


@pytest.mark.parametrize("body", [{"quantity": 0}, {"quantity": -1}, {"quantity": 10001}, {}, {"quantity": "x"}])
def test_quantity_validation(client, body):
    assert client.post("/stock/WMT-1001/reserve", json=body).status_code == 422


def test_metrics_expose_reservations_and_low_stock(client):
    ok = 'inventory_reservations_total{result="ok"}'
    bad = 'inventory_reservations_total{result="insufficient"}'
    ok0, bad0 = metric(client, ok), metric(client, bad)
    client.post("/stock/WMT-1001/reserve", json={"quantity": 1})
    client.post("/stock/WMT-1008/reserve", json={"quantity": 99})
    assert metric(client, ok) == ok0 + 1
    assert metric(client, bad) == bad0 + 1
    assert metric(client, "inventory_low_stock_skus") == 0.0
    assert 'http_requests_total{method="POST",path="/stock/{sku}/reserve",status="409"}' in client.get("/metrics").text


def test_low_stock_gauge_counts_skus_at_or_below_threshold(client):
    client.post("/stock/WMT-1008/reserve", json={"quantity": 36})  # 40 - 36 = 4 left
    assert "inventory_low_stock_skus 1.0" in client.get("/metrics").text


def metric(client, line_prefix):
    """Value of the first /metrics line starting with line_prefix (0.0 if absent)."""
    for line in client.get("/metrics").text.splitlines():
        if line.startswith(line_prefix):
            return float(line.rsplit(" ", 1)[1])
    return 0.0