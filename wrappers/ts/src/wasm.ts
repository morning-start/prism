/**
 * Low-level WASM runtime wrapper.
 *
 * Loads prism.wasm (classic `wasm` target) and calls the 11 exported
 * functions using the Prism string ABI:
 *
 *   - Every String argument is passed as an i32 linear-memory address.
 *   - At `ptr - 4` the runtime reads a u32 length (UTF-16 code units).
 *   - The string payload is UTF-16LE starting at `ptr`.
 *   - The i32 return value is an address with the same layout.
 *
 * This was verified end-to-end against `_build/wasm/debug/build/cmd/main/main.wasm`
 * (see wrappers/ts/README.md).
 */

import { readFileSync } from "fs";

// MoonBit WASM export names (classic wasm target emits them directly).
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

/** Prism WASM error. */
export class PrismError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PrismError";
  }
}

let _instance: WebAssembly.Instance | null = null;
let _memory: WebAssembly.Memory | null = null;
// Host-side scratch region for string arguments. Stays below the MoonBit
// GC heap (heap starts above ~0x1000; 0x2000 collides with it).
const SCRATCH_START = 0x0400;
const SCRATCH_STRIDE = 512;
let _scratch = SCRATCH_START;

/** Fresh view over the current linear memory (buffer may detach on grow). */
function bytes(): Uint8Array {
  return new Uint8Array((_memory as WebAssembly.Memory).buffer);
}

function dataView(): DataView {
  return new DataView((_memory as WebAssembly.Memory).buffer);
}

/** Encode a JS string as UTF-16LE at `ptr`, with length header at `ptr - 4`. */
function writeString(ptr: number, s: string): void {
  const view = bytes();
  const dv = dataView();
  dv.setUint32(ptr - 4, s.length, true);
  for (let i = 0; i < s.length; i++) {
    const code = s.charCodeAt(i);
    view[ptr + 2 * i] = code & 0xff;
    view[ptr + 2 * i + 1] = (code >> 8) & 0xff;
  }
}

/** Decode a UTF-16LE string returned by the runtime (length header at r - 4). */
function readString(ptr: number): string {
  const view = bytes();
  const dv = dataView();
  const len = dv.getUint32(ptr - 4, true);
  let out = "";
  for (let i = 0; i < len; i++) {
    out += String.fromCharCode(
      view[ptr + 2 * i] | (view[ptr + 2 * i + 1] << 8)
    );
  }
  return out;
}

/**
 * Load the prism.wasm binary.
 * @param wasmSource The .wasm file path or a Buffer with the wasm bytes.
 * @returns The WebAssembly instance.
 */
export function loadWasm(wasmSource: string | Buffer): WebAssembly.Instance {
  if (_instance) return _instance;

  const wasmBytes =
    typeof wasmSource === "string" ? readFileSync(wasmSource) : wasmSource;

  const module = new WebAssembly.Module(wasmBytes as unknown as ArrayBuffer);
  const instance = new WebAssembly.Instance(module, {});
  _instance = instance;
  _memory = instance.exports.memory as WebAssembly.Memory;
  // Run the runtime initializer before any conversion call.
  const start = instance.exports._start as (() => void) | undefined;
  if (typeof start === "function") start();
  _scratch = SCRATCH_START;
  return instance;
}

/** Reset the singleton (useful for testing). */
export function resetWasm(): void {
  _instance = null;
  _memory = null;
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

  // Write each string arg at a scratch address and pass the addresses.
  // Reset per call: a long-running host must never let _scratch grow into
  // the MoonBit GC heap (which starts above ~0x1000).
  _scratch = SCRATCH_START;
  const ptrs: number[] = [];
  for (const s of args) {
    writeString(_scratch, s);
    ptrs.push(_scratch);
    _scratch += SCRATCH_STRIDE;
  }

  const fn = exportFn as (...a: number[]) => number;
  const resultPtr = fn(...ptrs);
  const result = readString(resultPtr);

  if (result.startsWith('{"error":')) {
    throw new PrismError(result);
  }
  return result;
}
