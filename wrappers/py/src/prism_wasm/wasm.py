"""Low-level WASM runtime wrapper.

Loads the prism.wasm binary via wasmtime and exposes
the 11 exported functions as Python callables.
"""

from __future__ import annotations

import json
import struct
from pathlib import Path
from typing import Optional

import wasmtime

from prism_wasm.errors import PrismError

# MoonBit WASM export names (exported via options(link: ...) in moon.pkg).
# The export names match the original function names exactly.
_WASM_EXPORT_MAP: dict[str, str] = {
    "wasm_to_lux_req": "wasm_to_lux_req",
    "wasm_lux_req_to_provider": "wasm_lux_req_to_provider",
    "wasm_to_lux_resp": "wasm_to_lux_resp",
    "wasm_lux_resp_to_provider": "wasm_lux_resp_to_provider",
    "wasm_sse_to_events": "wasm_sse_to_events",
    "wasm_events_to_sse": "wasm_events_to_sse",
    "wasm_sdk_encode_req": "wasm_sdk_encode_req",
    "wasm_sdk_decode_resp": "wasm_sdk_decode_resp",
    "wasm_sdk_encode_stream": "wasm_sdk_encode_stream",
    "wasm_sdk_decode_sse": "wasm_sdk_decode_sse",
    "wasm_sdk_capability": "wasm_sdk_capability",
}


def _create_stubs(store: wasmtime.Store, module: wasmtime.Module) -> list:
    """Create stub imports for MoonBit runtime functions.

    Returns a flat list of import values matching the module's import order.
    """
    imports = []
    for imp in module.imports:
        import_type = imp.type
        if isinstance(import_type, wasmtime.FuncType):
            # Create a function stub that returns default values
            results = import_type.results

            def _make_handler(_results=results):
                def _handler(*args: list) -> list:
                    result_vals = []
                    for r in _results:
                        kind = r.kind
                        if kind == wasmtime.ValKind.I32:
                            result_vals.append(0)
                        elif kind == wasmtime.ValKind.I64:
                            result_vals.append(0)
                        elif kind == wasmtime.ValKind.F32:
                            result_vals.append(0.0)
                        elif kind == wasmtime.ValKind.F64:
                            result_vals.append(0.0)
                        else:
                            result_vals.append(None)
                    return result_vals

                return _handler

            func = wasmtime.Func(store, import_type, _make_handler())
            imports.append(func)
        elif isinstance(import_type, wasmtime.TagType):
            # Create a tag for exception handling
            tag = wasmtime.Tag(store, import_type)
            imports.append(tag)
        else:
            raise TypeError(f"Unsupported import type: {type(import_type)} for {imp.module}.{imp.name}")
    return imports


class WasmRuntime:
    """Singleton WASM runtime that loads prism.wasm once."""

    _instance: Optional["WasmRuntime"] = None

    def __init__(self, wasm_bytes: bytes) -> None:
        """Initialize the WASM runtime with raw .wasm bytes."""
        self._engine = wasmtime.Engine()
        self._module = wasmtime.Module(self._engine, wasm_bytes)
        self._store = wasmtime.Store(self._engine)

        # Create stubs for MoonBit runtime imports
        import_stubs = _create_stubs(self._store, self._module)

        self._instance = wasmtime.Instance(self._store, self._module, import_stubs)

        # Pre-resolve all exports
        self._exports: dict[str, wasmtime.Func] = {}
        for py_name, wasm_name in _WASM_EXPORT_MAP.items():
            func = self._instance.exports(self._store).get(wasm_name)
            if func is not None:
                self._exports[py_name] = func

        # Run the runtime initializer before any conversion call.
        start = self._instance.exports(self._store).get("_start")
        if start is not None:
            start(self._store)

    @classmethod
    def load(cls, wasm_source: bytes | str | Path) -> "WasmRuntime":
        """Load the WASM module (lazily cached).

        Args:
            wasm_source: Raw .wasm bytes, or a path to a .wasm file.

        Returns:
            A WasmRuntime instance.
        """
        if cls._instance is not None:
            return cls._instance

        if isinstance(wasm_source, (str, Path)):
            wasm_source = Path(wasm_source).read_bytes()

        cls._instance = cls(wasm_source)
        return cls._instance

    @classmethod
    def reset(cls) -> None:
        """Reset the singleton (useful for testing)."""
        cls._instance = None

    def _get_export(self, name: str) -> wasmtime.Func:
        """Get an exported function by friendly Python name."""
        func = self._exports.get(name)
        if func is None:
            raise PrismError(f"WASM export not found: {name}")
        return func

    def call(self, func_name: str, *args: str) -> str:
        """Call a WASM export function with string arguments.

        Prism string ABI: each String argument is an i32 linear-memory
        address where `ptr - 4` holds a u32 length (UTF-16 code units) and
        `ptr` holds the UTF-16LE payload. The i32 result is an address with
        the same layout. Scratch lives below the MoonBit GC heap.

        Args:
            func_name: The Python-friendly function name
                      (e.g. 'wasm_sdk_encode_req').
            *args: String arguments to pass.

        Returns:
            The result string from the WASM function.

        Raises:
            PrismError: If the WASM function returns an error JSON.
        """
        func = self._get_export(func_name)
        memory = self._instance.exports(self._store).get("memory")
        if memory is None:
            raise PrismError("WASM module has no memory export")

        ptr = 0x0400
        stride = 512
        call_args: list[int] = []
        for s in args:
            # UTF-16 code units, not code points: the utf-16-le codec
            # emits surrogate pairs for astral characters (e.g. emoji),
            # so the length header stays a true UTF-16 unit count.
            payload = s.encode("utf-16-le")
            units = len(payload) // 2
            # u32 length header at ptr-4 (UTF-16 code unit count).
            memory.write(self._store, struct.pack("<I", units), ptr - 4)
            memory.write(self._store, payload, ptr)
            call_args.append(ptr)
            ptr += stride

        result_ptr = func(self._store, *call_args)
        header = memory.read(self._store, result_ptr - 4, result_ptr)
        str_len = struct.unpack("<I", header)[0]
        raw = memory.read(self._store, result_ptr, result_ptr + 2 * str_len)
        result = raw.decode("utf-16-le")

        # Check for error response
        if result.startswith('{"error":'):
            err_msg = _parse_error(result)
            raise PrismError(err_msg)

        return result

    def call_json(self, func_name: str, *args: str) -> dict | list:
        """Call a WASM function and parse the result as JSON.

        Args:
            func_name: The exported function name.
            *args: String arguments.

        Returns:
            Parsed JSON result (dict or list).

        Raises:
            PrismError: If the WASM function returns an error, or JSON parse fails.
        """
        result = self.call(func_name, *args)
        try:
            return json.loads(result)
        except json.JSONDecodeError as e:
            raise PrismError(f"Failed to parse WASM result as JSON: {e}")


def _parse_error(json_str: str) -> str:
    """Extract error message from {'error': '...'} JSON."""
    try:
        obj = json.loads(json_str)
        return obj.get("error", str(obj))
    except json.JSONDecodeError:
        return json_str
