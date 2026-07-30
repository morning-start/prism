/** Low-level WASM runtime wrapper.

Loads the prism.wasm binary via Bun's built-in WebAssembly API.
MoonBit WASM exports use `__` instead of `_` (name mangling).
*/

import { readFileSync } from "fs";

// MoonBit WASM export names match the function names exactly
// (exported via options(link: ...) in moon.pkg).
const WASM_EXPORT_MAP: Record<string, string> = {
  wasm_to_lux_req: "wasm_to_lux_req",
  wasm_lux_req_to_provider: "wasm_lux_req_to_provider",
  wasm_to_lux_resp: "wasm_to_lux_resp",
  wasm_lux_resp_to_provider: "wasm_lux_resp_to_provider",
  wasm_sse_to_events: "wasm_sse_to_events",
  wasm_events_to_sse: "wasm_events_to_sse",
  wasm_sdk_encode_req: "wasm_sdk_encode_req",
  wasm_sdk_decode_resp: "wasm_sdk_decode_resp",
  wasm_sdk_encode_stream: "wasm_sdk_encode_stream",
  wasm_sdk_decode_sse: "wasm_sdk_decode_sse",
  wasm_sdk_capability: "wasm_sdk_capability",
};

type WasmFunc = (...args: number[]) => [number];

let _instance: WebAssembly.Instance | null = null;

/** Prism WASM error. */
export class PrismError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PrismError";
  }
}

/**
 * Load the prism.wasm binary.
 * @param wasmSource The .wasm file path or a Buffer with the wasm bytes.
 * @returns The WebAssembly instance.
 */
export function loadWasm(wasmSource: string | Buffer): WebAssembly.Instance {
  if (_instance) return _instance;

  const wasmBytes =
    typeof wasmSource === "string"
      ? readFileSync(wasmSource)
      : wasmSource;

  const module = new WebAssembly.Module(wasmBytes as unknown as ArrayBuffer);
  _instance = new WebAssembly.Instance(module, {});
  return _instance;
}

/** Reset the singleton (useful for testing). */
export function resetWasm(): void {
  _instance = null;
}

/**
 * Check if a result string is an error.
 * MoonBit WASM functions return '{"error":"message"}' on error.
 */
function isErrorResult(result: string): boolean {
  return result.startsWith('{"error":');
}

/**
 * Call a WASM export function with string arguments.
 * @param funcName Python-friendly function name (e.g. "wasm_sdk_encode_req")
 * @param args String arguments to pass
 * @returns The result string
 * @throws PrismError if the function is not found or returns an error
 */
export function callWasm(funcName: string, ...args: string[]): string {
  const inst = _instance;
  if (!inst) {
    throw new PrismError("WASM not loaded. Call loadWasm() first.");
  }

  const wasmName = WASM_EXPORT_MAP[funcName];
  if (!wasmName) {
    throw new PrismError(`Unknown WASM function: ${funcName}`);
  }

  const exportFn = inst.exports[wasmName as keyof WebAssembly.Exports];
  if (typeof exportFn !== "function") {
    throw new PrismError(
      `WASM export not found: ${wasmName} (mapped from ${funcName})`
    );
  }

  // MoonBit WASM functions expect string arguments as memory pointers.
  // This is a simplified call; the actual calling convention depends
  // on how MoonBit handles string parameters across WASM boundary.
  const fn = exportFn as (...a: number[]) => number;
  const result = fn(...args.map((s) => s.charCodeAt(0)));

  // In a full implementation, we'd need proper string marshalling
  // via WASM memory read/write. For now, this is a scaffold.
  return String(result);
}
