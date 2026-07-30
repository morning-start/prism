/** High-level Prism client API. */

import type { PrismOptions, PrismEvent } from "./types";
import { parseEvents } from "./types";
import { callWasm, loadWasm, PrismError } from "./wasm";
import { readFileSync } from "fs";

/**
 * Synchronous Prism client.
 * Wraps the 11 WASM exports into a clean TypeScript API.
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

  toLuxRequest(provider: string, jsonStr: string): string {
    return callWasm("wasm_to_lux_req", provider, jsonStr);
  }

  luxRequestToProvider(provider: string, luxJson: string): string {
    return callWasm("wasm_lux_req_to_provider", provider, luxJson);
  }

  toLuxResponse(provider: string, jsonStr: string): string {
    return callWasm("wasm_to_lux_resp", provider, jsonStr);
  }

  luxResponseToProvider(provider: string, luxJson: string): string {
    return callWasm("wasm_lux_resp_to_provider", provider, luxJson);
  }

  sseToEvents(provider: string, sseStr: string): string {
    return callWasm("wasm_sse_to_events", provider, sseStr);
  }

  eventsToSse(provider: string, eventsJson: string): string {
    return callWasm("wasm_events_to_sse", provider, eventsJson);
  }

  // ── High-level SDK API ──

  /** Encode a text request to provider JSON format. */
  encodeRequest(provider: string, text: string, opts?: PrismOptions): string {
    return callWasm("wasm_sdk_encode_req", provider, text);
  }

  /** Decode a provider JSON response to plain text. */
  decodeResponse(provider: string, jsonStr: string): string {
    return callWasm("wasm_sdk_decode_resp", provider, jsonStr);
  }

  /** Encode a text request for streaming. */
  encodeStream(provider: string, text: string, opts?: PrismOptions): string {
    return callWasm("wasm_sdk_encode_stream", provider, text);
  }

  /** Decode provider SSE text to PrismEvent list. */
  decodeSSE(provider: string, sseStr: string): PrismEvent[] {
    const result = callWasm("wasm_sdk_decode_sse", provider, sseStr);
    return parseEvents(result);
  }

  /** Query a provider's capability declaration. */
  capability(provider: string): Record<string, unknown> {
    const result = callWasm("wasm_sdk_capability", provider);
    return JSON.parse(result);
  }

  /** Cross-provider protocol conversion (Transit Middleware). */
  convert(
    fromProvider: string,
    toProvider: string,
    direction: "request" | "response",
    payload: string
  ): string {
    if (direction === "request") {
      const luxJson = this.toLuxRequest(fromProvider, payload);
      return this.luxRequestToProvider(toProvider, luxJson);
    } else {
      const luxJson = this.toLuxResponse(fromProvider, payload);
      return this.luxResponseToProvider(toProvider, luxJson);
    }
  }

  /** List all registered provider names. */
  listProviders(): string[] {
    return [
      "openai",
      "openai-chat",
      "anthropic",
      "gemini",
      "google-vertex",
      "azure-openai",
      "openai-codex",
    ];
  }

  /** Health check. */
  ping(): string {
    return "pong";
  }
}
