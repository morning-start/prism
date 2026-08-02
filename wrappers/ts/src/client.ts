/** High-level Prism client API. */

import type { PrismOptions, Envelope } from "./types";
import { parseEnvelope, envelopeValueString } from "./types";
import { callWasm, loadWasm } from "./wasm";
import { readFileSync } from "fs";

/**
 * Synchronous Prism client.
 * Wraps the 15 WASM exports into a clean TypeScript API.
 */
export class PrismClient {
  private loaded = false;

  /**
   * @param wasmSource Path to prism.wasm or a Buffer with the wasm bytes.
   */
  constructor(wasmSource: string | Buffer) {
    loadWasm(wasmSource);
    this.loaded = true;
  }

  // ── Low-level IR conversion ──
  // Each returns an Envelope: {"value":…,"diagnostics":[…]}

  toLuxRequest(provider: string, jsonStr: string): Envelope {
    return parseEnvelope(callWasm("wasm_to_lux_req", provider, jsonStr));
  }

  luxRequestToProvider(provider: string, luxJson: string): Envelope {
    return parseEnvelope(callWasm("wasm_lux_req_to_provider", provider, luxJson));
  }

  toLuxResponse(provider: string, jsonStr: string): Envelope {
    return parseEnvelope(callWasm("wasm_to_lux_resp", provider, jsonStr));
  }

  luxResponseToProvider(provider: string, luxJson: string): Envelope {
    return parseEnvelope(callWasm("wasm_lux_resp_to_provider", provider, luxJson));
  }

  sseToEvents(provider: string, sseStr: string): Envelope {
    return parseEnvelope(callWasm("wasm_sse_to_events", provider, sseStr));
  }

  eventsToSse(provider: string, eventsJson: string): Envelope {
    return parseEnvelope(callWasm("wasm_events_to_sse", provider, eventsJson));
  }

  // ── High-level SDK API ──
  // Each returns an Envelope: {"value":…,"diagnostics":[…]}

  /** Encode a text request to provider JSON format. */
  encodeRequest(provider: string, text: string, opts?: PrismOptions): Envelope {
    return parseEnvelope(callWasm("wasm_sdk_encode_req", provider, text));
  }

  /** Decode a provider JSON response to plain text. */
  decodeResponse(provider: string, jsonStr: string): Envelope {
    return parseEnvelope(callWasm("wasm_sdk_decode_resp", provider, jsonStr));
  }

  /** Encode a text request for streaming. */
  encodeStream(provider: string, text: string, opts?: PrismOptions): Envelope {
    return parseEnvelope(callWasm("wasm_sdk_encode_stream", provider, text));
  }

  /** Decode provider SSE text to PrismEvent list. */
  decodeSSE(provider: string, sseStr: string): Envelope {
    return parseEnvelope(callWasm("wasm_sdk_decode_sse", provider, sseStr));
  }

  /** Query a provider's capability declaration. */
  capability(provider: string): Envelope {
    return parseEnvelope(callWasm("wasm_sdk_capability", provider));
  }

  /** Cross-provider protocol conversion (Transit Middleware), single call. */
  convert(
    fromProvider: string,
    toProvider: string,
    direction: "request" | "response",
    payload: string
  ): string {
    const result =
      direction === "request"
        ? callWasm("wasm_convert_req", fromProvider, payload, toProvider)
        : callWasm("wasm_convert_resp", fromProvider, payload, toProvider);
    return envelopeValueString(parseEnvelope(result));
  }

  /** Convert streamed SSE text from one provider format to another. */
  convertStream(fromProvider: string, toProvider: string, sseStr: string): string {
    const result = callWasm("wasm_convert_stream", fromProvider, sseStr, toProvider);
    return envelopeValueString(parseEnvelope(result));
  }

  /** List all registered provider names from the WASM registry. */
  listProviders(): string[] {
    return JSON.parse(callWasm("wasm_list_providers")) as string[];
  }

  /** Health check. */
  ping(): string {
    return "pong";
  }
}
