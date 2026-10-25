// Prism TypeScript wrapper — binds the wasm-gc artifact (Node >= 22).
//
// Contract sources (single sources of truth, do not duplicate logic here):
//   - ABI exports:   src/cmd/main/moon.pkg (29-item list, wasm_abi_version = "1")
//   - Envelope:      {"value": <target JSON string>, "diagnostics": [{field, status, detail}]}
//                    error: {"error": "...", "diagnostics": []}
//   - Host contract: WebAssembly.instantiate(bytes, {}, { builtins: ['js-string'],
//                    importedStringConstants: '_' }) — missing options hard-fails.
//
// Wrapper layering rules (.agent-team/docs/04-API与数据契约.md):
//   不吞错、不重试、不降级 — the wrapper only decodes envelopes and maps types;
//   every diagnostic is passed through, every error becomes a thrown PrismError.

/** Fidelity class of a dropped/degraded field, mirroring the Lucent IR diagnostics. */
export type DiagnosticStatus = 'exact' | 'degraded' | 'unsupported' | 'invalid'

/** One diagnostic record from the wasm conversion envelope (passed through verbatim). */
export interface Diagnostic {
  readonly field: string
  readonly status: DiagnosticStatus
  readonly detail: string
}

export type PrismErrorCode =
  /** The host engine rejected the artifact (js-string builtins missing, Node < 22, corrupt bytes). */
  | 'LOAD_FAILED'
  /** The artifact does not export the 29-item ABI anchor set. */
  | 'MISSING_EXPORT'
  /** `wasm_abi_version` disagrees with the requested ABI. */
  | 'ABI_MISMATCH'
  /** wasm returned a payload that is not a valid envelope (integrity failure). */
  | 'ENVELOPE_INVALID'
  /** wasm returned an error envelope (e.g. unknown provider). */
  | 'CONVERSION_ERROR'
  /** Illegal stream session state (feed after finish, use after free, ...). */
  | 'SESSION_STATE'

export class PrismError extends Error {
  readonly code: PrismErrorCode
  readonly diagnostics: readonly Diagnostic[]

  constructor(
    code: PrismErrorCode,
    message: string,
    diagnostics: readonly Diagnostic[] = [],
    options?: ErrorOptions,
  ) {
    super(message, options)
    this.name = 'PrismError'
    this.code = code
    this.diagnostics = diagnostics
  }
}

/** Result of one conversion: the target-protocol JSON/SSE text plus surfaced diagnostics. */
export interface ConvertResult {
  /** Target wire payload exactly as produced by wasm — never re-serialized by the wrapper. */
  readonly value: string
  /** Diagnostics surfacing Exact/Degraded/Unsupported/Invalid decisions. Never swallowed. */
  readonly diagnostics: readonly Diagnostic[]
}

/** 29-item ABI anchor set; `src/cmd/main/moon.pkg` exports is the single source of truth. */
const CORE_EXPORTS: readonly string[] = [
  'wasm_to_lux_req', 'wasm_lux_req_to_provider', 'wasm_to_lux_resp', 'wasm_lux_resp_to_provider',
  'wasm_sse_to_events', 'wasm_events_to_sse',
  'wasm_sdk_encode_req', 'wasm_sdk_decode_resp', 'wasm_sdk_encode_stream', 'wasm_sdk_decode_sse',
  'wasm_sdk_capability',
  'wasm_convert_req', 'wasm_convert_resp', 'wasm_convert_stream', 'wasm_convert_stream_event',
  'wasm_stream_new', 'wasm_stream_feed', 'wasm_stream_finish', 'wasm_stream_finished',
  'wasm_stream_free',
  'wasm_list_providers', 'wasm_abi_version',
  'wasm_init_scratch', 'wasm_read_scratch_arg', 'wasm_log_init', 'wasm_log_pos',
  'wasm_convert_req_trace', 'wasm_convert_resp_trace', 'wasm_convert_stream_trace',
]

/**
 * The subset of the wasm ABI the wrapper binds. String params/returns are plain
 * JS strings because the artifact is built with `use-js-builtin-string`.
 */
interface RawExports {
  wasm_abi_version(): string
  wasm_convert_req(from: string, json: string, to: string): string
  wasm_convert_resp(from: string, json: string, to: string): string
  wasm_convert_stream(from: string, sse: string, to: string): string
  wasm_convert_stream_event(from: string, sseEvent: string, to: string): string
  wasm_list_providers(): string
  wasm_stream_new(from: string, to: string): string
  wasm_stream_feed(handle: number, chunk: string): string
  wasm_stream_finish(handle: number): string
  wasm_stream_finished(handle: number): string
  wasm_stream_free(handle: number): string
}

interface ParsedEnvelope {
  readonly value: unknown
  readonly diagnostics: readonly Diagnostic[]
}

function parseEnvelope(raw: string): ParsedEnvelope {
  let parsed: unknown
  try {
    parsed = JSON.parse(raw)
  } catch (cause) {
    throw new PrismError(
      'ENVELOPE_INVALID',
      `wasm returned a malformed envelope: ${raw.slice(0, 120)}`,
      [],
      { cause },
    )
  }
  if (parsed !== null && typeof parsed === 'object' && 'error' in (parsed as object)) {
    const err = parsed as { error: unknown }
    const message = typeof err.error === 'string' ? err.error : JSON.stringify(err.error)
    throw new PrismError('CONVERSION_ERROR', message)
  }
  const env = parsed as { value?: unknown; diagnostics?: unknown }
  if (
    typeof env?.value !== 'string'
    && !Array.isArray(env?.value)
    && typeof env?.value !== 'boolean'
    && typeof env?.value !== 'number'
    && (env?.value === null || typeof env?.value !== 'object')
  ) {
    throw new PrismError(
      'ENVELOPE_INVALID',
      `wasm envelope has no "value" field: ${raw.slice(0, 120)}`,
    )
  }
  const diags = Array.isArray(env.diagnostics) ? env.diagnostics : []
  return {
    value: env.value,
    diagnostics: diags as readonly Diagnostic[],
  }
}

/**
 * Parse a raw export return that is a bare JSON document (no envelope —
 * e.g. `wasm_list_providers` returns a bare string array).
 */
function parseBareJson<T>(raw: string, validate: (value: unknown) => T, context: string): T {
  let parsed: unknown
  try {
    parsed = JSON.parse(raw)
  } catch (cause) {
    throw new PrismError('ENVELOPE_INVALID', `${context}: value is not JSON: ${raw.slice(0, 120)}`, [], { cause })
  }
  return validate(parsed)
}

function expectString(value: unknown, context: string): string {
  if (typeof value !== 'string') {
    throw new PrismError('ENVELOPE_INVALID', `${context}: expected string, got ${typeof value}`)
  }
  return value
}

function expectFrameArray(value: unknown, context: string): readonly string[] {
  if (!Array.isArray(value) || !value.every(x => typeof x === 'string')) {
    throw new PrismError('ENVELOPE_INVALID', `${context}: expected an array of SSE frame strings`)
  }
  return value as readonly string[]
}

function expectBoolean(value: unknown, context: string): boolean {
  if (typeof value !== 'boolean') {
    throw new PrismError('ENVELOPE_INVALID', `${context}: expected boolean, got ${typeof value}`)
  }
  return value
}

/**
 * Binary wasm payload accepted by `WebAssembly.instantiate`
 * (ES-standard shapes; avoids a DOM-lib dependency for `BufferSource`).
 */
type WasmBytes = ArrayBuffer | ArrayBufferView

/**
 * Minimal structural typings for the WebAssembly JS API surface this wrapper
 * uses. Kept local (instead of pulling the DOM lib into tsconfig) so the
 * emitted .d.ts carries no lib requirements for consumers.
 */
interface WasmExportDescription {
  readonly name: string
  readonly kind: string
}
interface WasmModuleLike {
  exports(): readonly WasmExportDescription[]
}
interface WasmInstanceLike {
  readonly exports: unknown
}
interface WebAssemblyLike {
  Module: { exports(module: WasmModuleLike): readonly WasmExportDescription[] }
  instantiate(
    bytes: WasmBytes,
    importObject: Record<string, never>,
    options: { builtins: readonly string[]; importedStringConstants: string },
  ): Promise<{ module: WasmModuleLike; instance: WasmInstanceLike }>
}
/** Module-scoped ambient shadow of the runtime global; emits no code. */
declare const WebAssembly: WebAssemblyLike

export interface PrismOptions {
  /**
   * Expected `wasm_abi_version`. Defaults to "1". Load fails with
   * `ABI_MISMATCH` when the artifact disagrees — a rolling middleware should
   * refuse to run against a drifted artifact rather than silently misconvert.
   */
  readonly expectedAbi?: string
}

export class PrismClient {
  #raw: RawExports

  /** ABI version negotiated at load time (from `wasm_abi_version`). */
  readonly abiVersion: string
  /** Lucent IR schema version the artifact was built against. */
  readonly irSchema: string

  private constructor(raw: RawExports, abiVersion: string, irSchema: string) {
    this.#raw = raw
    this.abiVersion = abiVersion
    this.irSchema = irSchema
  }

  /**
   * Compile + instantiate a Prism wasm-gc artifact and return a typed client.
   *
   * - Validates the 29-item ABI anchor set up front (moonc silently ignores
   *   drifted export names — the consumer must anchor-check).
   * - Locks `wasm_abi_version` against `options.expectedAbi` (default "1").
   *
   * @throws {PrismError} LOAD_FAILED / MISSING_EXPORT / ABI_MISMATCH
   */
  static async load(bytes: WasmBytes, options: PrismOptions = {}): Promise<PrismClient> {
    const expectedAbi = options.expectedAbi ?? '1'
    let module: WasmModuleLike
    let instance: WasmInstanceLike
    try {
      ;({ module, instance } = await WebAssembly.instantiate(bytes, {}, {
        builtins: ['js-string'],
        importedStringConstants: '_',
      }))
    } catch (cause) {
      throw new PrismError(
        'LOAD_FAILED',
        'host engine rejected the wasm-gc artifact (requires js-string builtins: Node >= 22)',
        [],
        { cause },
      )
    }
    const names = WebAssembly.Module.exports(module).map(x => x.name)
    const missing = CORE_EXPORTS.filter(n => !names.includes(n))
    if (missing.length > 0) {
      throw new PrismError(
        'MISSING_EXPORT',
        `artifact is missing ${missing.length} ABI export(s): ${missing.join(', ')}`,
      )
    }
    const raw = instance.exports as RawExports
    // value is the version document object {"abi":"1","ir_schema":"v1"}
    const abiEnv = parseEnvelope(raw.wasm_abi_version())
    const abiDoc = abiEnv.value as { abi?: unknown; ir_schema?: unknown }
    if (abiDoc === null || typeof abiDoc !== 'object' || typeof abiDoc.abi !== 'string') {
      throw new PrismError(
        'ENVELOPE_INVALID',
        `wasm_abi_version: value is not a version document: ${JSON.stringify(abiEnv.value)}`,
      )
    }
    if (abiDoc.abi !== expectedAbi) {
      throw new PrismError(
        'ABI_MISMATCH',
        `artifact abi "${String(abiDoc.abi)}" != expected "${expectedAbi}" (ir_schema ${String(abiDoc.ir_schema)})`,
      )
    }
    return new PrismClient(raw, abiDoc.abi, String(abiDoc.ir_schema ?? ''))
  }

  /** Provider request JSON: `from` protocol → Lucent IR-free direct `to` protocol. */
  convertRequest(from: string, json: string, to: string): ConvertResult {
    const env = parseEnvelope(this.#raw.wasm_convert_req(from, json, to))
    return { value: expectString(env.value, 'wasm_convert_req'), diagnostics: env.diagnostics }
  }

  /** Provider response JSON: `from` protocol → `to` protocol. */
  convertResponse(from: string, json: string, to: string): ConvertResult {
    const env = parseEnvelope(this.#raw.wasm_convert_resp(from, json, to))
    return { value: expectString(env.value, 'wasm_convert_resp'), diagnostics: env.diagnostics }
  }

  /** Whole provider SSE text: `from` protocol → `to` protocol. */
  convertStream(from: string, sse: string, to: string): ConvertResult {
    const env = parseEnvelope(this.#raw.wasm_convert_stream(from, sse, to))
    return { value: expectString(env.value, 'wasm_convert_stream'), diagnostics: env.diagnostics }
  }

  /** One SSE event: `from` protocol → `to` protocol. */
  convertStreamEvent(from: string, sseEvent: string, to: string): ConvertResult {
    const env = parseEnvelope(this.#raw.wasm_convert_stream_event(from, sseEvent, to))
    return { value: expectString(env.value, 'wasm_convert_stream_event'), diagnostics: env.diagnostics }
  }

  /**
   * Open an incremental stream session. Feed source chunks as they arrive;
   * call `finish()` in a `finally` block (termination contract, CR-002).
   */
  createStream(from: string, to: string): StreamSession {
    const env = parseEnvelope(this.#raw.wasm_stream_new(from, to))
    const handle = env.value
    if (typeof handle !== 'number' || !Number.isInteger(handle)) {
      throw new PrismError('ENVELOPE_INVALID', 'wasm_stream_new: expected an integer handle')
    }
    return new StreamSession(this.#raw, handle)
  }

  /** All provider primary names known to the artifact (bare JSON array — no envelope). */
  listProviders(): readonly string[] {
    return parseBareJson(
      this.#raw.wasm_list_providers(),
      value => {
        if (!Array.isArray(value) || !value.every(x => typeof x === 'string')) {
          throw new PrismError('ENVELOPE_INVALID', 'wasm_list_providers: expected a bare JSON array of strings')
        }
        return value as readonly string[]
      },
      'wasm_list_providers',
    )
  }
}

/**
 * Incremental stream session over the `wasm_stream_*` handle ABI (CR-002).
 *
 * Termination contract: `finish()` flushes the trailing half-frame and the
 * held Finish frame — call it in a `finally` block. A session abandoned
 * without `finish()` keeps its wasm slot until `free()`; `free()` is idempotent.
 */
export class StreamSession {
  #raw: RawExports
  #handle: number
  #finished = false
  #freed = false

  constructor(raw: RawExports, handle: number) {
    this.#raw = raw
    this.#handle = handle
  }

  /** Feed one source chunk (may contain partial SSE text); returns target frames produced by it. */
  feed(chunk: string): readonly string[] {
    this.#assertOpen('feed()')
    const env = parseEnvelope(this.#raw.wasm_stream_feed(this.#handle, chunk))
    return expectFrameArray(env.value, 'wasm_stream_feed')
  }

  /**
   * Flush the trailing half-frame + held Finish frame. Idempotent: a second
   * call returns `[]` (safe under `finally` double-invocation).
   */
  finish(): readonly string[] {
    if (this.#freed) {
      throw new PrismError('SESSION_STATE', 'finish() called on a freed stream session')
    }
    if (this.#finished) return []
    this.#finished = true
    const env = parseEnvelope(this.#raw.wasm_stream_finish(this.#handle))
    return expectFrameArray(env.value, 'wasm_stream_finish')
  }

  /** Host-side self-check: has the session been terminated (finish flushes → true)? */
  finished(): boolean {
    if (this.#freed) return true
    if (this.#finished) return true
    const env = parseEnvelope(this.#raw.wasm_stream_finished(this.#handle))
    return expectBoolean(env.value, 'wasm_stream_finished')
  }

  /** Release the wasm session slot. Idempotent. */
  free(): void {
    if (this.#freed) return
    this.#freed = true
    const env = parseEnvelope(this.#raw.wasm_stream_free(this.#handle))
    expectBoolean(env.value, 'wasm_stream_free')
  }

  #assertOpen(op: string): void {
    if (this.#freed) {
      throw new PrismError('SESSION_STATE', `${op} called on a freed stream session`)
    }
    if (this.#finished) {
      throw new PrismError('SESSION_STATE', `${op} called after finish() — stream already terminated`)
    }
  }
}

/**
 * Compile + instantiate a Prism wasm-gc artifact and return a typed client.
 * Convenience free-function form of {@link PrismClient.load} — identical
 * validation and error codes.
 *
 * @throws {PrismError} LOAD_FAILED / MISSING_EXPORT / ABI_MISMATCH
 */
export async function loadPrism(bytes: WasmBytes, options: PrismOptions = {}): Promise<PrismClient> {
  return PrismClient.load(bytes, options)
}
