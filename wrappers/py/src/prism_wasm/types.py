"""Prism WASM type definitions."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Optional


class FinishReason(str, Enum):
    """Reason why the LLM finished generating."""

    STOP = "stop"
    LENGTH = "length"
    TOOL_CALLS = "tool_calls"
    CONTENT_FILTER = "content_filter"
    ERROR = "error"


@dataclass
class PrismOptions:
    """Options for encoding a request."""

    model: Optional[str] = None
    temperature: Optional[float] = None
    max_tokens: Optional[int] = None

    def to_json(self) -> str:
        """Serialize to JSON string."""
        parts: list[str] = []
        if self.model is not None:
            parts.append(f'"model":"{_json_escape(self.model)}"')
        if self.temperature is not None:
            parts.append(f'"temperature":{self.temperature}')
        if self.max_tokens is not None:
            parts.append(f'"max_tokens":{self.max_tokens}')
        return "{" + ",".join(parts) + "}"


@dataclass
class TextDeltaEvent:
    """A text delta event."""

    type: str = "text_delta"
    text: str = ""


@dataclass
class ToolCallEvent:
    """A tool call event."""

    type: str = "tool_call"
    id: str = ""
    name: str = ""
    arguments_json: str = ""


@dataclass
class ToolResultEvent:
    """A tool result event."""

    type: str = "tool_result"
    tool_use_id: str = ""
    content: str = ""
    is_error: bool = False


@dataclass
class ThinkingEvent:
    """A thinking (reasoning) event."""

    type: str = "thinking"
    text: str = ""


@dataclass
class FinishEvent:
    """A finish event."""

    type: str = "finish"
    reason: FinishReason = FinishReason.STOP


PrismEvent = TextDeltaEvent | ToolCallEvent | ToolResultEvent | ThinkingEvent | FinishEvent


def _json_escape(s: str) -> str:
    """Escape a string for JSON."""
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")


def parse_event(json_obj: dict) -> PrismEvent:
    """Parse a PrismEvent from a JSON dict."""
    event_type = json_obj.get("type", "")
    if event_type == "text_delta":
        return TextDeltaEvent(text=json_obj.get("text", ""))
    elif event_type == "tool_call":
        return ToolCallEvent(
            id=json_obj.get("id", ""),
            name=json_obj.get("name", ""),
            arguments_json=json_obj.get("arguments", ""),
        )
    elif event_type == "tool_result":
        return ToolResultEvent(
            tool_use_id=json_obj.get("tool_use_id", ""),
            content=json_obj.get("content", ""),
            is_error=json_obj.get("is_error", False),
        )
    elif event_type == "thinking":
        return ThinkingEvent(text=json_obj.get("text", ""))
    elif event_type == "finish":
        reason = FinishReason(json_obj.get("reason", "stop"))
        return FinishEvent(reason=reason)
    else:
        raise ValueError(f"Unknown event type: {event_type}")


def parse_events(json_str: str) -> list[PrismEvent]:
    """Parse a JSON array of events."""
    import json

    raw = json.loads(json_str)
    return [parse_event(item) for item in raw]
