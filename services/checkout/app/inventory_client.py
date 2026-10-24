import httpx


class InventoryUnavailable(Exception):
    """The inventory service could not be reached or answered with a 5xx."""


class InventoryRejected(Exception):
    """The inventory service understood the request and said no (4xx)."""

    def __init__(self, status_code, detail):
        super().__init__(detail)
        self.status_code = status_code
        self.detail = detail


class InventoryClient:
    def __init__(self, base_url, timeout=2.0, transport=None):
        self._client = httpx.Client(base_url=base_url, timeout=timeout, transport=transport)

    def reserve(self, sku, quantity):
        return self._post(f"/stock/{sku}/reserve", quantity)

    def release(self, sku, quantity):
        return self._post(f"/stock/{sku}/release", quantity)

    def _post(self, path, quantity):
        try:
            response = self._client.post(path, json={"quantity": quantity})
        except httpx.HTTPError as exc:
            raise InventoryUnavailable(exc.__class__.__name__) from exc
        if response.status_code >= 500:
            raise InventoryUnavailable(f"inventory returned {response.status_code}")
        if response.status_code >= 400:
            try:
                detail = response.json().get("detail", response.text)
            except ValueError:
                detail = response.text
            raise InventoryRejected(response.status_code, detail)
        return response.json()