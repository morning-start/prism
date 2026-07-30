"""Tests for the Prism WASM Python wrapper."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from prism_wasm import PrismClient, PrismOptions
from prism_wasm.errors import PrismError
from prism_wasm.types import FinishReason, TextDeltaEvent, FinishEvent, parse_events
from prism_wasm.wasm import WasmRuntime, _WASM_EXPORT_MAP

WASM_PATH = Path(__file__).parent.parent / "prism.wasm"


@pytest.fixture(scope="module")
def client() -> PrismClient:
    if not WASM_PATH.exists():
        pytest.skip(f"prism.wasm not found at {WASM_PATH}")
    return PrismClient(WASM_PATH.read_bytes())


class TestWasmExports:
    """Verify all expected WASM exports are present."""

    def test_all_exports_found(self, client: PrismClient):
        """All 11 wasm_* exports were resolved during loading."""
        runtime = client._wasm
        for py_name, wasm_name in _WASM_EXPORT_MAP.items():
            assert py_name in runtime._exports, f"Missing export: {py_name}"
        assert len(runtime._exports) == 11


class TestListProviders:
    def test_returns_known_providers(self, client: PrismClient):
        providers = client.list_providers()
        assert "openai" in providers
        assert "anthropic" in providers
        assert len(providers) > 0


class TestPing:
    def test_returns_pong(self, client: PrismClient):
        assert client.ping() == "pong"


class TestParseEvents:
    def test_parse_text_delta(self):
        json_str = json.dumps([{"type": "text_delta", "text": "你好"}])
        events = parse_events(json_str)
        assert len(events) == 1
        assert events[0].type == "text_delta"
        if isinstance(events[0], TextDeltaEvent):
            assert events[0].text == "你好"

    def test_parse_finish(self):
        json_str = json.dumps([{"type": "finish", "reason": "stop"}])
        events = parse_events(json_str)
        assert len(events) == 1
        assert events[0].type == "finish"
        if isinstance(events[0], FinishEvent):
            assert events[0].reason == FinishReason.STOP

    def test_parse_multiple(self):
        json_str = json.dumps([
            {"type": "text_delta", "text": "Hello"},
            {"type": "finish", "reason": "stop"},
        ])
        events = parse_events(json_str)
        assert len(events) == 2

    def test_parse_empty(self):
        events = parse_events("[]")
        assert len(events) == 0

    def test_parse_unknown_type(self):
        json_str = json.dumps([{"type": "unknown_event"}])
        with pytest.raises(ValueError, match="Unknown event type"):
            parse_events(json_str)
