"""Prism WASM error types."""


class PrismError(Exception):
    """Base error for Prism WASM operations.

    Raised when a WASM function returns an error JSON.
    """

    def __init__(self, message: str) -> None:
        self.message = message
        super().__init__(message)


class ProviderNotFoundError(PrismError):
    """Unknown provider name."""


class JsonParseError(PrismError):
    """JSON parse failure in WASM layer."""
