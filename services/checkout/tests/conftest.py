import httpx
import pytest
from fastapi.testclient import TestClient

from app import main
from app.inventory_client import InventoryClient


class FakeInventory:
    """An httpx transport that behaves like the inventory service and records every call."""

    def __init__(self, stock):
        self.stock = dict(stock)
        self.calls = []

    def __call__(self, request: httpx.Request) -> httpx.Response:
        _, _, sku, action = request.url.path.split("/")
        qty = int(request.read().decode().split(":")[1].strip(" }"))
        self.calls.append((action, sku, qty))
        if sku not in self.stock:
            return httpx.Response(404, json={"detail": f"SKU {sku} not found"})
        if action == "reserve":
            if self.stock[sku] < qty:
                return httpx.Response(409, json={"detail": f"Insufficient stock for {sku}"})
            self.stock[sku] -= qty
        else:
            self.stock[sku] += qty
        return httpx.Response(200, json={"sku": sku, "available": self.stock[sku]})


@pytest.fixture(autouse=True)
def clean_orders():
    main._orders.clear()
    yield
    main.app.dependency_overrides.clear()


@pytest.fixture
def fake():
    return FakeInventory({"A": 10, "B": 2})


@pytest.fixture
def client(fake):
    inventory = InventoryClient("http://inventory", transport=httpx.MockTransport(fake))
    main.app.dependency_overrides[main.get_inventory] = lambda: inventory
    return TestClient(main.app)


@pytest.fixture
def client_inventory_down():
    def refuse(request):
        raise httpx.ConnectError("connection refused")

    inventory = InventoryClient("http://inventory", transport=httpx.MockTransport(refuse))
    main.app.dependency_overrides[main.get_inventory] = lambda: inventory
    return TestClient(main.app)