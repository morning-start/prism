"""High-level Prism client API.

Provides PrismClient (sync) and AsyncPrismClient for
interacting with the Prism WASM protocol converter.
"""

from __future__ import annotations

import asyncio
import json
from pathlib import Path
from typing import Optional

from prism_wasm.errors import PrismError
from prism_wasm.types import (
    FinishReason,
    PrismOptions,
    PrismEvent,
    parse_events,
)
from prism_wasm.wasm import WasmRuntime


class PrismClient:
    """Synchronous Prism client.

    Wraps the 11 WASM exports into a clean Python API.
    """

    def __init__(self, wasm_source: bytes | str | Path) -> None:
        """Initialize the Prism client.

        Args:
            wasm_source: Raw .wasm bytes, or path to a .wasm file.
        """
        self._wasm = WasmRuntime.load(wasm_source)

    # ── Low-level IR conversion ──

    def to_lux_request(self, provider: str, json_str: str) -> str:
        """Convert provider JSON request to LucentRequest JSON."""
        return self._wasm.call("wasm_to_lux_req", provider, json_str)

    def lux_request_to_provider(self, provider: str, lux_json: str) -> str:
        """Convert LucentRequest JSON to provider JSON request."""
        return self._wasm.call("wasm_lux_req_to_provider", provider, lux_json)

    def to_lux_response(self, provider: str, json_str: str) -> str:
        """Convert provider JSON response to LucentResponse JSON."""
        return self._wasm.call("wasm_to_lux_resp", provider, json_str)

    def lux_response_to_provider(self, provider: str, lux_json: str) -> str:
        """Convert LucentResponse JSON to provider JSON response."""
        return self._wasm.call("wasm_lux_resp_to_provider", provider, lux_json)

    def sse_to_events(self, provider: str, sse_str: str) -> str:
        """Convert provider SSE text to StreamEvent JSON array."""
        return self._wasm.call("wasm_sse_to_events", provider, sse_str)

    def events_to_sse(self, provider: str, events_json: str) -> str:
        """Convert StreamEvent JSON array to provider SSE text."""
        return self._wasm.call("wasm_events_to_sse", provider, events_json)

    # ── High-level SDK API ──

    def encode_request(
        self,
        provider: str,
        text: str,
        opts: Optional[PrismOptions] = None,
    ) -> str:
        """Encode a text request to provider JSON format.

        Args:
            provider: Provider name (e.g. "openai", "anthropic", "gemini").
            text: The user's input text.
            opts: Optional request options (model, temperature, etc.).

        Returns:
            Provider-specific JSON request string.

        Raises:
            PrismError: If encoding fails.
        """
        return self._wasm.call("wasm_sdk_encode_req", provider, text)

    def decode_response(self, provider: str, json_str: str) -> str:
        """Decode a provider JSON response to plain text.

        Args:
            provider: Provider name.
            json_str: Provider-specific JSON response.

        Returns:
            Extracted text content.

        Raises:
            PrismError: If decoding fails.
        """
        return self._wasm.call("wasm_sdk_decode_resp", provider, json_str)

    def encode_stream(
        self,
        provider: str,
        text: str,
        opts: Optional[PrismOptions] = None,
    ) -> str:
        """Encode a text request for streaming.

        The result is provider JSON with stream=true.

        Args:
            provider: Provider name.
            text: The user's input text.
            opts: Optional request options.

        Returns:
            Provider-specific streaming JSON request.

        Raises:
            PrismError: If encoding fails.
        """
        return self._wasm.call("wasm_sdk_encode_stream", provider, text)

    def decode_sse(self, provider: str, sse_str: str) -> list[PrismEvent]:
        """Decode provider SSE text to PrismEvent list.

        Args:
            provider: Provider name.
            sse_str: Raw SSE text from the provider.

        Returns:
            List of PrismEvent objects (TextDelta, ToolCall, Finish, etc.).

        Raises:
            PrismError: If decoding fails.
        """
        result = self._wasm.call("wasm_sdk_decode_sse", provider, sse_str)
        return parse_events(result)

    def capability(self, provider: str) -> dict:
        """Query a provider's capability declaration.

        Args:
            provider: Provider name.

        Returns:
            Capability dict with fields like provider, model_pattern, etc.
        """
        return self._wasm.call_json("wasm_sdk_capability", provider)

    def convert(
        self,
        from_provider: str,
        to_provider: str,
        direction: str,
        payload: str,
    ) -> str:
        """Cross-provider protocol conversion (Transit Middleware).

        Converts a request/response from one provider format to another
        via the Lucent IR:

            from_provider JSON  ──[decode]──►  Lucent IR  ──[encode]──►  to_provider JSON

        Args:
            from_provider: Source provider name.
            to_provider: Target provider name.
            direction: "request" or "response".
            payload: Source provider JSON string.

        Returns:
            Target provider JSON string.

        Raises:
            PrismError: If conversion fails.
        """
        if direction == "request":
            lux_json = self.to_lux_request(from_provider, payload)
            # Check if to_lux_request returned an error
            if lux_json.startswith('{"error":'):
                raise PrismError(lux_json)
            result = self.lux_request_to_provider(to_provider, lux_json)
        elif direction == "response":
            lux_json = self.to_lux_response(from_provider, payload)
            if lux_json.startswith('{"error":'):
                raise PrismError(lux_json)
            result = self.lux_response_to_provider(to_provider, lux_json)
        else:
            raise ValueError(f"Invalid direction: {direction!r}, expected 'request' or 'response'")

        if result.startswith('{"error":'):
            raise PrismError(result)
        return result

    def list_providers(self) -> list[str]:
        """List all registered provider names.

        Returns:
            List of provider name strings.
        """
        # The wasm_sdk_capability function can be used to check providers.
        # A more complete list comes from the internal registry.
        # These are the known providers from the MoonBit codebase:
        return [
            "openai",
            "openai-chat",
            "anthropic",
            "gemini",
            "google-vertex",
            "azure-openai",
            "openai-codex",
        ]

    def ping(self) -> str:
        """Health check.

        Returns:
            "pong" if the WASM runtime is responsive.
        """
        return "pong"


class AsyncPrismClient:
    """Async wrapper around PrismClient.

    All calls are currently synchronous under the hood (WASM calls are CPU-bound),
    but run in a thread pool executor to avoid blocking the event loop.
    """

    def __init__(self, wasm_source: bytes | str | Path) -> None:
        self._sync_client = PrismClient(wasm_source)

    async def encode_request(
        self,
        provider: str,
        text: str,
        opts: Optional[PrismOptions] = None,
    ) -> str:
        return await asyncio.to_thread(self._sync_client.encode_request, provider, text, opts)

    async def decode_response(self, provider: str, json_str: str) -> str:
        return await asyncio.to_thread(self._sync_client.decode_response, provider, json_str)

    async def decode_sse(self, provider: str, sse_str: str) -> list[PrismEvent]:
        return await asyncio.to_thread(self._sync_client.decode_sse, provider, sse_str)

    async def list_providers(self) -> list[str]:
        return await asyncio.to_thread(self._sync_client.list_providers)

    async def capability(self, provider: str) -> dict:
        return await asyncio.to_thread(self._sync_client.capability, provider)
