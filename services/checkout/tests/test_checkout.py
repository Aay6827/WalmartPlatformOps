import httpx
import pytest

from app import main as checkout_main
from app.inventory_client import CircuitBreaker, InventoryClient


def order(items, customer="C-1"):
    return {"customer_id": customer, "items": items}


def test_health(client):
    assert client.get("/health/live").json() == {"status": "alive"}
    assert client.get("/health/ready").json()["service"] == "checkout"


def test_checkout_confirms_and_reserves_stock(client, fake):
    r = client.post("/checkout", json=order([{"sku": "A", "quantity": 3}]))
    assert r.status_code == 201
    body = r.json()
    assert body["status"] == "CONFIRMED" and body["id"] == 1
    assert fake.stock["A"] == 7
    assert client.get("/orders/1").json() == body


def test_duplicate_skus_are_combined_into_one_reservation(client, fake):
    client.post("/checkout", json=order([{"sku": "A", "quantity": 2}, {"sku": "A", "quantity": 3}]))
    assert fake.calls == [("reserve", "A", 5)]


def test_insufficient_stock_is_409_and_earlier_reservations_are_rolled_back(client, fake):
    r = client.post("/checkout", json=order([{"sku": "A", "quantity": 4}, {"sku": "B", "quantity": 99}]))
    assert r.status_code == 409
    assert fake.stock == {"A": 10, "B": 2}  # A was reserved, then given back
    assert ("release", "A", 4) in fake.calls
    assert client.get("/orders/1").status_code == 404  # no order was created


def test_unknown_sku_is_404(client):
    assert client.post("/checkout", json=order([{"sku": "NOPE", "quantity": 1}])).status_code == 404


def test_inventory_down_gives_503_and_marks_dependency_down(client_inventory_down):
    r = client_inventory_down.post("/checkout", json=order([{"sku": "A", "quantity": 1}]))
    assert r.status_code == 503
    assert metric(client_inventory_down, "inventory_dependency_up") == 0.0
    assert metric(client_inventory_down, 'checkout_requests_total{result="inventory_unavailable"}') >= 1.0


def test_readiness_does_not_depend_on_inventory(client_inventory_down):
    assert client_inventory_down.get("/health/ready").status_code == 200


def test_dependency_recovers_after_a_good_call(client, fake):
    client.post("/checkout", json=order([{"sku": "A", "quantity": 1}]))
    assert metric(client, "inventory_dependency_up") == 1.0


@pytest.mark.parametrize(
    "body",
    [
        {"customer_id": "C", "items": []},
        {"customer_id": "", "items": [{"sku": "A", "quantity": 1}]},
        {"customer_id": "C", "items": [{"sku": "A", "quantity": 0}]},
        {"customer_id": "C", "items": [{"sku": "A", "quantity": 1001}]},
        {"items": [{"sku": "A", "quantity": 1}]},
    ],
)
def test_validation(client, body):
    assert client.post("/checkout", json=body).status_code == 422


def test_metrics_count_outcomes(client):
    conf = 'checkout_requests_total{result="confirmed"}'
    rej = 'checkout_requests_total{result="rejected"}'
    http = 'http_requests_total{method="POST",path="/checkout",status="201"}'
    c0, r0, h0 = metric(client, conf), metric(client, rej), metric(client, http)
    client.post("/checkout", json=order([{"sku": "A", "quantity": 1}]))
    client.post("/checkout", json=order([{"sku": "B", "quantity": 99}]))
    assert metric(client, conf) == c0 + 1
    assert metric(client, rej) == r0 + 1
    assert metric(client, http) == h0 + 1


def metric(client, line_prefix):
    """Value of the first /metrics line starting with line_prefix (0.0 if absent)."""
    for line in client.get("/metrics").text.splitlines():
        if line.startswith(line_prefix):
            return float(line.rsplit(" ", 1)[1])
    return 0.0


# ---------- circuit breaker ----------
class FakeClock:
    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now


def test_breaker_opens_after_consecutive_failures_and_probes_after_reset():
    clock = FakeClock()
    b = CircuitBreaker(failure_threshold=3, reset_seconds=5.0, clock=clock)
    for _ in range(2):
        assert b.allow()
        b.record_failure()
    assert b.allow() and not b.is_open  # two failures: still closed
    b.record_failure()
    assert b.is_open and not b.allow()  # third failure opens it
    clock.now = 4.9
    assert not b.allow()
    clock.now = 5.0
    assert b.allow()  # the single probe
    assert not b.allow()  # nobody else gets through while the probe is in flight
    b.record_failure()  # probe failed: open again
    assert b.is_open and not b.allow()
    clock.now = 10.0
    assert b.allow()
    b.record_success()  # probe succeeded: closed
    assert not b.is_open and b.allow()


def test_success_resets_the_failure_count():
    b = CircuitBreaker(failure_threshold=3)
    b.record_failure()
    b.record_failure()
    b.record_success()
    b.record_failure()
    b.record_failure()
    assert not b.is_open


def test_open_circuit_answers_503_without_touching_the_network(client_inventory_down):
    attempts = []

    def refuse(request):
        attempts.append(request)
        raise httpx.ConnectError("connection refused")

    inventory = InventoryClient("http://inventory", transport=httpx.MockTransport(refuse))
    checkout_main.app.dependency_overrides[checkout_main.get_inventory] = lambda: inventory
    codes = [client_inventory_down.post("/checkout", json=order([{"sku": "A", "quantity": 1}])).status_code for _ in range(6)]
    assert codes == [503] * 6
    assert len(attempts) == 3  # three real attempts, then the breaker refused the rest
    assert metric(client_inventory_down, "inventory_circuit_open") == 1.0


def test_client_4xx_does_not_open_the_circuit(client):
    for _ in range(5):
        assert client.post("/checkout", json=order([{"sku": "NOPE", "quantity": 1}])).status_code == 404
    assert client.post("/checkout", json=order([{"sku": "A", "quantity": 1}])).status_code == 201