"""Pluggable transports for the Prism client (ARCHITECTURE.md §6).

Each transport speaks JSON-RPC 2.0 over a different wire protocol:
HTTP (POST + SSE streaming), Unix domain socket (JSON lines), WebSocket
(one message per frame).
"""

import json
import socket
import threading
from typing import Any, Dict, List, Optional

import httpx
import websockets.sync.client


class RPCError(Exception):
    """JSON-RPC error returned by the daemon."""

    def __init__(self, code: int, message: str):
        super().__init__(f"rpc error {code}: {message}")
        self.code = code
        self.message = message


class Transport:
    """Call performs one JSON-RPC request; Stream streams response frames."""

    def call(self, method: str, params: Dict[str, Any]) -> bytes:
        raise NotImplementedError

    def stream(self, method: str, params: Dict[str, Any]) -> List[bytes]:
        raise NotImplementedError


def _request(method: str, params: Dict[str, Any]) -> Dict[str, Any]:
    return {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}


def _decode(data: bytes) -> Dict[str, Any]:
    resp = json.loads(data)
    if "error" in resp and resp["error"] is not None:
        err = resp["error"]
        raise RPCError(err.get("code", -1), err.get("message", "unknown error"))
    return resp["result"]


class HTTPTransport(Transport):
    """JSON-RPC over HTTP POST; streaming via Accept: text/event-stream."""

    def __init__(self, base_url: str):
        self.base_url = base_url.rstrip("/")

    def call(self, method: str, params: Dict[str, Any]) -> bytes:
        with httpx.Client(timeout=30) as client:
            resp = client.post(self.base_url, json=_request(method, params))
            resp.raise_for_status()
            return resp.content

    def stream(self, method: str, params: Dict[str, Any]) -> List[bytes]:
        frames: List[bytes] = []
        with httpx.Client(timeout=60) as client:
            with client.stream(
                "POST",
                self.base_url,
                json=_request(method, params),
                headers={"Accept": "text/event-stream"},
            ) as resp:
                resp.raise_for_status()
                cur: List[str] = []
                for line in resp.iter_lines():
                    if line == "":
                        if cur:
                            frames.append("\n".join(cur).encode("utf-8"))
                            cur = []
                        continue
                    if line.startswith("data:"):
                        cur = [line[len("data:"):].strip()]
        return frames


class UDSTransport(Transport):
    """JSON-RPC over a Unix domain socket using JSON lines."""

    def __init__(self, sock_path: str):
        self.sock_path = sock_path

    def _roundtrip(self, payload: str, stream: bool) -> List[bytes]:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
            conn.settimeout(30)
            conn.connect(self.sock_path)
            conn.sendall((payload + "\n").encode("utf-8"))
            buf = b""
            lines: List[bytes] = []
            while True:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                buf += chunk
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    if line.strip():
                        lines.append(line.strip())
                        if not stream or b'"type":"done"' in line:
                            return lines
            return lines

    def call(self, method: str, params: Dict[str, Any]) -> bytes:
        payload = json.dumps(_request(method, params))
        lines = self._roundtrip(payload, stream=False)
        return lines[0]

    def stream(self, method: str, params: Dict[str, Any]) -> List[bytes]:
        payload = json.dumps(_request(method, params))
        return self._roundtrip(payload, stream=True)


class WSTransport(Transport):
    """JSON-RPC over WebSocket, one message per frame."""

    def __init__(self, url: str):
        self.url = url

    def _roundtrip(self, payload: str, stream: bool) -> List[bytes]:
        frames: List[bytes] = []
        with websockets.sync.client.connect(self.url, close_timeout=5) as ws:
            ws.send(payload)
            while True:
                data = ws.recv()
                frames.append(data if isinstance(data, bytes) else data.encode("utf-8"))
                if not stream or b'"type":"done"' in frames[-1]:
                    return frames

    def call(self, method: str, params: Dict[str, Any]) -> bytes:
        payload = json.dumps(_request(method, params))
        return self._roundtrip(payload, stream=False)[0]

    def stream(self, method: str, params: Dict[str, Any]) -> List[bytes]:
        payload = json.dumps(_request(method, params))
        return self._roundtrip(payload, stream=True)
