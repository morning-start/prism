/**
 * Prism WASM - LLM protocol converter for TypeScript (Bun).
 *
 * Prism converts between different LLM provider formats via a neutral
 * intermediate representation (Lucent IR).
 *
 * Usage:
 * ```typescript
 * import { PrismClient } from "@morning-start/prism-wasm";
 * import { readFileSync } from "fs";
 *
 * const client = new PrismClient(readFileSync("prism.wasm"));
 *
 * // Encode a request: text -> OpenAI JSON
 * const req = client.encodeRequest("openai", "Hello!");
 * console.log(req);
 *
 * // Decode a response: OpenAI JSON -> text
 * const text = client.decodeResponse("openai", respJson);
 * console.log(text);
 * ```
 */

export { PrismClient } from "./client";
export type {
  PrismOptions,
  PrismEvent,
  FinishReason,
  TextDeltaEvent,
  ToolCallEvent,
  ToolResultEvent,
  ThinkingEvent,
  FinishEvent,
} from "./types";
export { parseEvent, parseEvents } from "./types";
export { PrismError } from "./wasm";
