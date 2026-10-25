import threading
import time

import httpx


class InventoryUnavailable(Exception):
    """The inventory service could not be reached or answered with a 5xx."""


class CircuitOpen(InventoryUnavailable):
    """Not even attempted: recent calls failed, so the circuit is open."""


class InventoryRejected(Exception):
    """The inventory service understood the request and said no (4xx)."""

    def __init__(self, status_code, detail):
        super().__init__(detail)
        self.status_code = status_code
        self.detail = detail


class CircuitBreaker:
    """Fail fast when a dependency is down instead of waiting on the network for every request.

    closed    -> calls flow; `failure_threshold` consecutive failures open the circuit
    open      -> calls are refused immediately for `reset_seconds`
    half-open -> after that, exactly one probe call is let through: success closes, failure re-opens
    """

    def __init__(self, failure_threshold=3, reset_seconds=5.0, clock=time.monotonic):
        self._threshold = failure_threshold
        self._reset = reset_seconds
        self._clock = clock
        self._lock = threading.Lock()
        self._failures = 0
        self._state = "closed"
        self._opened_at = 0.0

    @property
    def is_open(self):
        return self._state != "closed"

    def allow(self):
        with self._lock:
            if self._state == "closed":
                return True
            if self._state == "open" and self._clock() - self._opened_at >= self._reset:
                self._state = "half-open"
                return True  # this caller is the probe
            return False

    def record_success(self):
        with self._lock:
            self._failures = 0
            self._state = "closed"

    def record_failure(self):
        with self._lock:
            self._failures += 1
            if self._state == "half-open" or self._failures >= self._threshold:
                self._state = "open"
                self._opened_at = self._clock()


class InventoryClient:
    def __init__(self, base_url, timeout=2.0, connect_timeout=0.5, transport=None, breaker=None):
        self._client = httpx.Client(
            base_url=base_url,
            timeout=httpx.Timeout(timeout, connect=connect_timeout),
            transport=transport,
        )
        self.breaker = breaker or CircuitBreaker()

    def reserve(self, sku, quantity):
        return self._post(f"/stock/{sku}/reserve", quantity)

    def release(self, sku, quantity):
        return self._post(f"/stock/{sku}/release", quantity)

    def _post(self, path, quantity):
        if not self.breaker.allow():
            raise CircuitOpen("circuit open")
        try:
            response = self._client.post(path, json={"quantity": quantity})
        except httpx.HTTPError as exc:
            self.breaker.record_failure()
            raise InventoryUnavailable(exc.__class__.__name__) from exc
        if response.status_code >= 500:
            self.breaker.record_failure()
            raise InventoryUnavailable(f"inventory returned {response.status_code}")
        # Any answer below 500 (including a 4xx "no") proves the service is alive.
        self.breaker.record_success()
        if response.status_code >= 400:
            try:
                detail = response.json().get("detail", response.text)
            except ValueError:
                detail = response.text
            raise InventoryRejected(response.status_code, detail)
        return response.json()