"""PrismClient — unified SDK interface over a pluggable transport.

Method set mirrors ARCHITECTURE.md §6.1; every method maps 1:1 to a daemon
RPC and parses the D5 envelope {value, diagnostics}.
"""

import json
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

from .transport import RPCError, Transport


@dataclass
class Diagnostic:
    field: str
    status: str
    detail: Optional[str] = None

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "Diagnostic":
        return cls(field=d.get("field", ""), status=d.get("status", ""), detail=d.get("detail"))


@dataclass
class Envelope:
    value: Any
    diagnostics: List[Diagnostic] = field(default_factory=list)

    @classmethod
    def from_result(cls, result: Dict[str, Any]) -> "Envelope":
        diags = [Diagnostic.from_dict(d) for d in result.get("diagnostics", [])]
        return cls(value=result.get("value"), diagnostics=diags)

    def value_string(self) -> str:
        if isinstance(self.value, str):
            return self.value
        return json.dumps(self.value)


@dataclass
class Event:
    type: str
    text: Optional[str] = None
    id: Optional[str] = None
    name: Optional[str] = None
    arguments: Optional[str] = None
    tool_use_id: Optional[str] = None
    content: Optional[str] = None
    is_error: Optional[bool] = None
    reason: Optional[str] = None

    @classmethod
    def from_value(cls, value: Any) -> "Event":
        if isinstance(value, dict):
            return cls(**{k: v for k, v in value.items() if k in cls.__dataclass_fields__})
        return cls(type="done")


class PrismClient:
    def __init__(self, transport: Transport):
        self._tr = transport

    def call_raw(self, method: str, params: Dict[str, Any]) -> Envelope:
        data = self._tr.call(method, params)
        parsed = json.loads(data)
        if "error" in parsed and parsed["error"] is not None:
            err = parsed["error"]
            raise RPCError(err.get("code", -1), err.get("message", "unknown error"))
        return Envelope.from_result(parsed["result"])

    def encode_request(self, provider: str, text: str) -> Envelope:
        return self.call_raw("encode_request", {"provider": provider, "text": text})

    def decode_response(self, provider: str, resp_json: str) -> Envelope:
        return self.call_raw("decode_response", {"provider": provider, "json": resp_json})

    def decode_sse(self, provider: str, sse: str) -> Envelope:
        return self.call_raw("decode_sse", {"provider": provider, "sse": sse})

    def encode_stream(self, provider: str, text: str) -> Envelope:
        return self.call_raw("encode_stream", {"provider": provider, "text": text})

    def convert(
        self, from_provider: str, to_provider: str, direction: str, payload: str
    ) -> Envelope:
        return self.call_raw(
            "convert",
            {
                "from_provider": from_provider,
                "to_provider": to_provider,
                "direction": direction,
                "payload": payload,
            },
        )

    def convert_stream(self, from_provider: str, to_provider: str, sse: str) -> Envelope:
        return self.call_raw(
            "convert_stream",
            {"from_provider": from_provider, "to_provider": to_provider, "sse": sse},
        )

    def list_providers(self) -> List[str]:
        env = self.call_raw("list_providers", {})
        return list(env.value)

    def capability(self, provider: str) -> Envelope:
        return self.call_raw("capability", {"provider": provider})

    def ping(self) -> str:
        env = self.call_raw("ping", {})
        return env.value_string()

    def stream_decode_sse(self, provider: str, sse: str) -> List[Event]:
        frames = self._tr.stream("decode_sse", {"provider": provider, "sse": sse})
        events: List[Event] = []
        for frame in frames:
            result = json.loads(frame)
            if "error" in result and result["error"] is not None:
                raise RuntimeError(result["error"])
            ev = Event.from_value(result["result"]["value"])
            events.append(ev)
            if ev.type == "done":
                break
        return events
