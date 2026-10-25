import os
import threading
import time
from collections import defaultdict

from fastapi import Depends, FastAPI, HTTPException, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest
from pydantic import BaseModel, Field

from app.inventory_client import InventoryClient, InventoryRejected, InventoryUnavailable

SERVICE_NAME = os.getenv("SERVICE_NAME", "checkout")
APP_VERSION = os.getenv("APP_VERSION", "1.0.0")
INVENTORY_URL = os.getenv("INVENTORY_URL", "http://inventory:8000")
INVENTORY_TIMEOUT = float(os.getenv("INVENTORY_TIMEOUT_SECONDS", "2.0"))
INVENTORY_CONNECT_TIMEOUT = float(os.getenv("INVENTORY_CONNECT_TIMEOUT_SECONDS", "0.5"))

HTTP_REQUESTS = Counter("http_requests_total", "Total HTTP requests", ["method", "path", "status"])
HTTP_LATENCY = Histogram("http_request_duration_seconds", "HTTP request latency in seconds", ["method", "path"])
CHECKOUTS = Counter("checkout_requests_total", "Checkout attempts by result", ["result"])
INVENTORY_CALL_LATENCY = Histogram("inventory_call_duration_seconds", "Latency of calls to the inventory service")
INVENTORY_UP = Gauge("inventory_dependency_up", "1 if the last inventory call reached the service, else 0")
INVENTORY_CIRCUIT_OPEN = Gauge("inventory_circuit_open", "1 while the circuit breaker is refusing calls to inventory")

app = FastAPI(title="Checkout Service", version=APP_VERSION)

_orders = {}
_orders_lock = threading.Lock()
_inventory = None


def get_inventory():
    global _inventory
    if _inventory is None:
        _inventory = InventoryClient(INVENTORY_URL, timeout=INVENTORY_TIMEOUT, connect_timeout=INVENTORY_CONNECT_TIMEOUT)
    return _inventory


class Item(BaseModel):
    sku: str = Field(min_length=1, max_length=32)
    quantity: int = Field(gt=0, le=1000)


class CheckoutRequest(BaseModel):
    customer_id: str = Field(min_length=1, max_length=32)
    items: list[Item] = Field(min_length=1, max_length=50)


@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    start = time.perf_counter()
    status_code = 500
    try:
        response = await call_next(request)
        status_code = response.status_code
        return response
    finally:
        route = request.scope.get("route")
        path = route.path if route else "unmatched"
        if path != "/metrics":
            HTTP_REQUESTS.labels(request.method, path, str(status_code)).inc()
            HTTP_LATENCY.labels(request.method, path).observe(time.perf_counter() - start)


@app.get("/health/live")
def live():
    return {"status": "alive"}


@app.get("/health/ready")
def ready():
    # Deliberately does not probe inventory: if readiness depended on it, an inventory
    # outage would take every checkout pod out of service and turn a partial failure into
    # a total one. Dependency health is reported by inventory_dependency_up instead.
    return {"status": "ready", "service": SERVICE_NAME, "version": APP_VERSION}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


def _call(fn, *args):
    start = time.perf_counter()
    try:
        result = fn(*args)
    except InventoryUnavailable:
        INVENTORY_UP.set(0)
        raise
    else:
        INVENTORY_UP.set(1)
        return result
    finally:
        INVENTORY_CALL_LATENCY.observe(time.perf_counter() - start)
        breaker = getattr(fn.__self__, "breaker", None)
        if breaker is not None:
            INVENTORY_CIRCUIT_OPEN.set(1 if breaker.is_open else 0)


def _roll_back(inventory, reserved):
    """Best effort: give back everything reserved so far."""
    for sku, qty in reserved:
        try:
            _call(inventory.release, sku, qty)
        except (InventoryUnavailable, InventoryRejected):
            pass


@app.post("/checkout", status_code=201)
def checkout(body: CheckoutRequest, inventory: InventoryClient = Depends(get_inventory)):
    wanted = defaultdict(int)
    for item in body.items:
        wanted[item.sku] += item.quantity

    reserved = []
    try:
        for sku, qty in wanted.items():
            _call(inventory.reserve, sku, qty)
            reserved.append((sku, qty))
    except InventoryRejected as exc:
        _roll_back(inventory, reserved)
        CHECKOUTS.labels("rejected").inc()
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    except InventoryUnavailable:
        _roll_back(inventory, reserved)
        CHECKOUTS.labels("inventory_unavailable").inc()
        raise HTTPException(status_code=503, detail="Inventory service unavailable, please retry")

    with _orders_lock:
        order_id = len(_orders) + 1
        order = {
            "id": order_id,
            "customer_id": body.customer_id,
            "items": [{"sku": s, "quantity": q} for s, q in wanted.items()],
            "status": "CONFIRMED",
        }
        _orders[order_id] = order
    CHECKOUTS.labels("confirmed").inc()
    return order


@app.get("/orders/{order_id}")
def get_order(order_id: int):
    order = _orders.get(order_id)
    if order is None:
        raise HTTPException(status_code=404, detail="Order not found")
    return order