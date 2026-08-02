"""High-level Prism client API.

Provides PrismClient (sync) and AsyncPrismClient for
interacting with the Prism WASM protocol converter.
"""

from __future__ import annotations

import asyncio
import json
from pathlib import Path
from typing import Optional

from prism_wasm.types import (
    Envelope,
    PrismOptions,
    parse_envelope,
)
from prism_wasm.wasm import WasmRuntime


class PrismClient:
    """Synchronous Prism client.

    Wraps the 15 WASM exports into a clean Python API.
    """

    def __init__(self, wasm_source: bytes | str | Path) -> None:
        """Initialize the Prism client.

        Args:
            wasm_source: Raw .wasm bytes, or path to a .wasm file.
        """
        self._wasm = WasmRuntime.load(wasm_source)

    # ── Low-level IR conversion ──
    # Each returns an Envelope: {"value":…,"diagnostics":[…]}

    def to_lux_request(self, provider: str, json_str: str) -> Envelope:
        """Convert provider JSON request to LucentRequest JSON."""
        return parse_envelope(self._wasm.call("wasm_to_lux_req", provider, json_str))

    def lux_request_to_provider(self, provider: str, lux_json: str) -> Envelope:
        """Convert LucentRequest JSON to provider JSON request."""
        return parse_envelope(
            self._wasm.call("wasm_lux_req_to_provider", provider, lux_json)
        )

    def to_lux_response(self, provider: str, json_str: str) -> Envelope:
        """Convert provider JSON response to LucentResponse JSON."""
        return parse_envelope(self._wasm.call("wasm_to_lux_resp", provider, json_str))

    def lux_response_to_provider(self, provider: str, lux_json: str) -> Envelope:
        """Convert LucentResponse JSON to provider JSON response."""
        return parse_envelope(
            self._wasm.call("wasm_lux_resp_to_provider", provider, lux_json)
        )

    def sse_to_events(self, provider: str, sse_str: str) -> Envelope:
        """Convert provider SSE text to StreamEvent JSON array."""
        return parse_envelope(self._wasm.call("wasm_sse_to_events", provider, sse_str))

    def events_to_sse(self, provider: str, events_json: str) -> Envelope:
        """Convert StreamEvent JSON array to provider SSE text."""
        return parse_envelope(
            self._wasm.call("wasm_events_to_sse", provider, events_json)
        )

    # ── High-level SDK API ──

    def encode_request(
        self,
        provider: str,
        text: str,
        opts: Optional[PrismOptions] = None,
    ) -> Envelope:
        """Encode a text request to provider JSON format.

        Args:
            provider: Provider name (e.g. "openai", "anthropic", "gemini").
            text: The user's input text.
            opts: Optional request options (model, temperature, etc.).

        Returns:
            Envelope with value = provider-specific JSON request string and
            diagnostics from schema validation.

        Raises:
            PrismError: If encoding fails.
        """
        return parse_envelope(self._wasm.call("wasm_sdk_encode_req", provider, text))

    def decode_response(self, provider: str, json_str: str) -> Envelope:
        """Decode a provider JSON response to plain text.

        Args:
            provider: Provider name.
            json_str: Provider-specific JSON response.

        Returns:
            Envelope with value = extracted text string and diagnostics.

        Raises:
            PrismError: If decoding fails.
        """
        return parse_envelope(
            self._wasm.call("wasm_sdk_decode_resp", provider, json_str)
        )

    def encode_stream(
        self,
        provider: str,
        text: str,
        opts: Optional[PrismOptions] = None,
    ) -> Envelope:
        """Encode a text request for streaming.

        The result is provider JSON with stream=true.

        Args:
            provider: Provider name.
            text: The user's input text.
            opts: Optional request options.

        Returns:
            Envelope with value = provider-specific streaming JSON request.

        Raises:
            PrismError: If encoding fails.
        """
        return parse_envelope(
            self._wasm.call("wasm_sdk_encode_stream", provider, text)
        )

    def decode_sse(self, provider: str, sse_str: str) -> Envelope:
        """Decode provider SSE text to PrismEvent list.

        Args:
            provider: Provider name.
            sse_str: Raw SSE text from the provider.

        Returns:
            Envelope with value = list of PrismEvent objects
            (TextDelta, ToolCall, Finish, etc.).

        Raises:
            PrismError: If decoding fails.
        """
        return parse_envelope(self._wasm.call("wasm_sdk_decode_sse", provider, sse_str))

    def capability(self, provider: str) -> Envelope:
        """Query a provider's capability declaration.

        Args:
            provider: Provider name.

        Returns:
            Envelope with value = capability dict with fields like provider,
            model_pattern, etc.
        """
        return parse_envelope(self._wasm.call("wasm_sdk_capability", provider))

    def convert(
        self,
        from_provider: str,
        to_provider: str,
        direction: str,
        payload: str,
    ) -> str:
        """Cross-provider protocol conversion (Transit Middleware).

        Converts a request/response from one provider format to another
        via the Lucent IR, in a single WASM call:

            from_provider JSON  ──[wasm_convert_req/resp]──►  to_provider JSON

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
            result = self._wasm.call("wasm_convert_req", from_provider, payload, to_provider)
        elif direction == "response":
            result = self._wasm.call("wasm_convert_resp", from_provider, payload, to_provider)
        else:
            raise ValueError(f"Invalid direction: {direction!r}, expected 'request' or 'response'")
        env = parse_envelope(result)
        return env.value_string()

    def convert_stream(self, from_provider: str, to_provider: str, sse_str: str) -> str:
        """Convert streamed SSE text from one provider format to another.

        Args:
            from_provider: Source provider name.
            to_provider: Target provider name.
            sse_str: Raw SSE text from the source provider.

        Returns:
            Target provider SSE text.

        Raises:
            PrismError: If conversion fails.
        """
        env = parse_envelope(
            self._wasm.call("wasm_convert_stream", from_provider, sse_str, to_provider)
        )
        return env.value_string()

    def list_providers(self) -> list[str]:
        """List all registered provider names from the WASM registry.

        Returns:
            List of provider name strings.
        """
        return self._wasm.call_json("wasm_list_providers")

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
    ) -> Envelope:
        return await asyncio.to_thread(self._sync_client.encode_request, provider, text, opts)

    async def decode_response(self, provider: str, json_str: str) -> Envelope:
        return await asyncio.to_thread(self._sync_client.decode_response, provider, json_str)

    async def decode_sse(self, provider: str, sse_str: str) -> Envelope:
        return await asyncio.to_thread(self._sync_client.decode_sse, provider, sse_str)

    async def list_providers(self) -> list[str]:
        return await asyncio.to_thread(self._sync_client.list_providers)

    async def capability(self, provider: str) -> Envelope:
        return await asyncio.to_thread(self._sync_client.capability, provider)
