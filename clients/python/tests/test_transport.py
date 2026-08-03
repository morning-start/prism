"""Prism Python SDK tests: same assertions across HTTP / UDS / WS transports.

The test builds the prism-daemon binary once, starts it with HTTP + UDS + WS
listeners, and runs the pluggable-transport contract against each.
"""

import json
import os
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import httpx
import pytest

from prism.client import PrismClient
from prism.transport import HTTPTransport, RPCError, UDSTransport, WSTransport

REPO_ROOT = Path(__file__).resolve().parents[3]
WASM_PATH = REPO_ROOT / "_build" / "wasm" / "debug" / "build" / "cmd" / "main" / "main.wasm"
DAEMON_DIR = REPO_ROOT / "transport" / "daemon"

# UDS 属 Linux/macOS 传输（ARCHITECTURE.md §5.2，Windows 用 Named Pipe）；
# Python 在 Windows 上无 socket.AF_UNIX，故 UDS 用例在无 AF_UNIX 的平台跳过。
UDS_SKIP = not hasattr(socket, "AF_UNIX")
UDS_REASON = "socket.AF_UNIX not available on this platform"


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@pytest.fixture(scope="module")
def daemon():
    if not WASM_PATH.exists():
        pytest.skip("classic wasm build not found, run: moon build --target wasm")

    # Build the daemon binary once.
    tmp = Path(tempfile.mkdtemp(prefix="prism-py-"))
    binary = tmp / ("prism-daemon.exe" if os.name == "nt" else "prism-daemon")
    subprocess.run(
        ["go", "build", "-o", str(binary), "./cmd/prism-daemon"],
        cwd=DAEMON_DIR,
        check=True,
        capture_output=True,
    )

    http_port, ws_port = _free_port(), _free_port()
    while ws_port == http_port:
        ws_port = _free_port()  # 端口冲突会导致 HTTP/WS 监听互斥，daemon 无法就绪
    uds_path = str(tmp / "prism.sock")
    proc = subprocess.Popen(
        [
            str(binary),
            "--wasm", str(WASM_PATH),
            "--listen", f"127.0.0.1:{http_port}",
            "--uds", uds_path,
            "--ws", f"127.0.0.1:{ws_port}",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    # Wait for HTTP readiness (trust_env=False: 本地 daemon 不走系统代理).
    deadline = time.time() + 15
    probe = httpx.Client(trust_env=False, timeout=1)
    last_err: Optional[Exception] = None
    while time.time() < deadline:
        if proc.poll() is not None:
            out, err = proc.communicate()
            pytest.fail(
                f"daemon exited early: {proc.returncode}\nSTDOUT: {out[-500:]}\nSTDERR: {err[-500:]}"
            )
        try:
            resp = probe.get(f"http://127.0.0.1:{http_port}/health")
            resp.raise_for_status()
            break
        except Exception as e:  # noqa: BLE001
            last_err = e
            time.sleep(0.1)
    else:
        proc.terminate()
        out, err = proc.communicate(timeout=3)
        pytest.fail(
            f"daemon did not become ready; last probe error: {last_err!r}\n"
            f"STDOUT: {out[-500:]}\nSTDERR: {err[-500:]}"
        )
    probe.close()

    yield {
        "http": f"http://127.0.0.1:{http_port}/v1",
        "uds": uds_path,
        "ws": f"ws://127.0.0.1:{ws_port}/ws",
    }
    proc.terminate()
    proc.wait(timeout=5)


def _client(daemon, name: str) -> PrismClient:
    transports = {
        "http": HTTPTransport(daemon["http"]),
        "uds": UDSTransport(daemon["uds"]),
        "ws": WSTransport(daemon["ws"]),
    }
    return PrismClient(transports[name])


def _sse_fixture() -> str:
    return (
        'data: {"choices":[{"delta":{"role":"assistant"}}]}\n\n'
        'data: {"choices":[{"delta":{"content":"Hello"}}]}\n\n'
        'data: {"choices":[{"delta":{},"finish_reason":"stop"}}]}\n\n'
        "data: [DONE]\n"
    )


@pytest.mark.parametrize("transport", ["http", "uds", "ws"])
def test_ping(daemon, transport):
    if transport == "uds" and UDS_SKIP:
        pytest.skip(UDS_REASON)
    env = _client(daemon, transport).ping()
    assert env == "pong"


@pytest.mark.parametrize("transport", ["http", "uds", "ws"])
def test_encode_request(daemon, transport):
    if transport == "uds" and UDS_SKIP:
        pytest.skip(UDS_REASON)
    env = _client(daemon, transport).encode_request("openai-chat", "Hi")
    assert '"messages"' in env.value_string()


@pytest.mark.parametrize("transport", ["http", "uds", "ws"])
def test_convert(daemon, transport):
    if transport == "uds" and UDS_SKIP:
        pytest.skip(UDS_REASON)
    client = _client(daemon, transport)
    req = client.encode_request("openai-chat", "Hi")
    env = client.convert("openai-chat", "anthropic", "request", req.value_string())
    assert env.diagnostics is not None
    assert ("system" in env.value_string()) or ("messages" in env.value_string())


@pytest.mark.parametrize("transport", ["http", "uds", "ws"])
def test_stream_decode_sse(daemon, transport):
    if transport == "uds" and UDS_SKIP:
        pytest.skip(UDS_REASON)
    client = _client(daemon, transport)
    events = client.stream_decode_sse("openai-chat", _sse_fixture())
    assert len(events) >= 2
    assert events[-1].type == "done"


@pytest.mark.parametrize("transport", ["http", "uds", "ws"])
def test_unknown_method(daemon, transport):
    if transport == "uds" and UDS_SKIP:
        pytest.skip(UDS_REASON)
    client = _client(daemon, transport)
    with pytest.raises(Exception) as exc:
        client.call_raw("nope", {})
    assert "method" in str(exc.value)
