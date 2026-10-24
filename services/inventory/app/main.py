import os
import threading
import time

from fastapi import FastAPI, HTTPException, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest
from pydantic import BaseModel, Field

SERVICE_NAME = os.getenv("SERVICE_NAME", "inventory")
APP_VERSION = os.getenv("APP_VERSION", "1.0.0")
LOW_STOCK_THRESHOLD = int(os.getenv("LOW_STOCK_THRESHOLD", "5"))

SEED = {
    "WMT-1001": ("Great Value Rice 5kg", 500),
    "WMT-1002": ("Great Value Whole Milk 1L", 500),
    "WMT-1003": ("Mainstays Desk Lamp", 500),
    "WMT-1004": ("Ozark Trail Water Bottle", 500),
    "WMT-1005": ("Parents Choice Diapers", 500),
    "WMT-1006": ("Marketside Salad Kit", 500),
    "WMT-1007": ("Mainstays Bath Towel", 500),
    "WMT-1008": ("Limited Edition Thermos", 40),
}

HTTP_REQUESTS = Counter("http_requests_total", "Total HTTP requests", ["method", "path", "status"])
HTTP_LATENCY = Histogram("http_request_duration_seconds", "HTTP request latency in seconds", ["method", "path"])
RESERVATIONS = Counter("inventory_reservations_total", "Reservation attempts by result", ["result"])
LOW_STOCK_SKUS = Gauge("inventory_low_stock_skus", "SKUs at or below the low-stock threshold")


class Store:
    """In-memory stock. Deliberately simple: this project is about delivery, not persistence."""

    def __init__(self, seed):
        self._lock = threading.Lock()
        self._seed = seed
        self._items = self._load(seed)

    @staticmethod
    def _load(seed):
        return {
            sku: {"sku": sku, "name": name, "on_hand": qty, "reserved": 0}
            for sku, (name, qty) in seed.items()
        }

    def reset(self):
        with self._lock:
            self._items = self._load(self._seed)

    @staticmethod
    def _view(item):
        return {**item, "available": item["on_hand"] - item["reserved"]}

    def list(self):
        with self._lock:
            return [self._view(i) for i in sorted(self._items.values(), key=lambda i: i["sku"])]

    def get(self, sku):
        with self._lock:
            item = self._items.get(sku)
            return self._view(item) if item else None

    def reserve(self, sku, qty):
        with self._lock:
            item = self._items.get(sku)
            if item is None:
                return "unknown", None
            if item["on_hand"] - item["reserved"] < qty:
                return "insufficient", self._view(item)
            item["reserved"] += qty
            return "ok", self._view(item)

    def release(self, sku, qty):
        with self._lock:
            item = self._items.get(sku)
            if item is None:
                return "unknown", None
            if item["reserved"] < qty:
                return "too_many", self._view(item)
            item["reserved"] -= qty
            return "ok", self._view(item)

    def low_stock_count(self):
        with self._lock:
            return sum(1 for i in self._items.values() if i["on_hand"] - i["reserved"] <= LOW_STOCK_THRESHOLD)


store = Store(SEED)
app = FastAPI(title="Inventory Service", version=APP_VERSION)


class Quantity(BaseModel):
    quantity: int = Field(gt=0, le=10000)


@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    start = time.perf_counter()
    status_code = 500  # an unhandled exception reaches the client as a 500
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
    return {"status": "ready", "service": SERVICE_NAME, "version": APP_VERSION}


@app.get("/metrics")
def metrics():
    LOW_STOCK_SKUS.set(store.low_stock_count())
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/stock")
def list_stock():
    return store.list()


@app.get("/stock/{sku}")
def get_stock(sku: str):
    item = store.get(sku)
    if item is None:
        raise HTTPException(status_code=404, detail=f"SKU {sku} not found")
    return item


@app.post("/stock/{sku}/reserve")
def reserve(sku: str, body: Quantity):
    result, item = store.reserve(sku, body.quantity)
    RESERVATIONS.labels(result).inc()
    if result == "unknown":
        raise HTTPException(status_code=404, detail=f"SKU {sku} not found")
    if result == "insufficient":
        raise HTTPException(
            status_code=409,
            detail=f"Insufficient stock for {sku}: requested {body.quantity}, available {item['available']}",
        )
    return item


@app.post("/stock/{sku}/release")
def release(sku: str, body: Quantity):
    result, item = store.release(sku, body.quantity)
    if result == "unknown":
        raise HTTPException(status_code=404, detail=f"SKU {sku} not found")
    if result == "too_many":
        raise HTTPException(
            status_code=409,
            detail=f"Cannot release {body.quantity} of {sku}: only {item['reserved']} reserved",
        )
    return item