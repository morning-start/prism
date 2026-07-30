"""Prism WASM - LLM protocol converter.

Prism converts between different LLM provider formats (OpenAI, Anthropic,
Gemini, etc.) via a neutral intermediate representation (Lucent IR).

Usage:
    from prism_wasm import PrismClient

    # Load the WASM binary and create a client
    client = PrismClient("prism.wasm")

    # Encode a request: text -> provider JSON
    req_json = client.encode_request("openai", "Hello!")
    print(req_json)

    # Decode a response: provider JSON -> text
    text = client.decode_response("openai", resp_json)
    print(text)
"""

from prism_wasm.client import AsyncPrismClient, PrismClient
from prism_wasm.types import (
    FinishEvent,
    FinishReason,
    PrismEvent,
    PrismOptions,
    TextDeltaEvent,
    ThinkingEvent,
    ToolCallEvent,
    ToolResultEvent,
)

__all__ = [
    "PrismClient",
    "AsyncPrismClient",
    "PrismOptions",
    "PrismEvent",
    "TextDeltaEvent",
    "ToolCallEvent",
    "ToolResultEvent",
    "ThinkingEvent",
    "FinishEvent",
    "FinishReason",
]
