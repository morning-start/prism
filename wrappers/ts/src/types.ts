/** Prism WASM type definitions. */

/** Options for encoding a request. */
export interface PrismOptions {
  model?: string;
  temperature?: number;
  max_tokens?: number;
}

/** Reason why the LLM finished generating. */
export type FinishReason =
  | "stop"
  | "length"
  | "tool_calls"
  | "content_filter"
  | "error";

/** A text delta event. */
export interface TextDeltaEvent {
  type: "text_delta";
  text: string;
}

/** A tool call event. */
export interface ToolCallEvent {
  type: "tool_call";
  id: string;
  name: string;
  arguments: string;
}

/** A tool result event. */
export interface ToolResultEvent {
  type: "tool_result";
  tool_use_id: string;
  content: string;
  is_error: boolean;
}

/** A thinking (reasoning) event. */
export interface ThinkingEvent {
  type: "thinking";
  text: string;
}

/** A finish event. */
export interface FinishEvent {
  type: "finish";
  reason: FinishReason;
}

/** A Prism event (union type). */
export type PrismEvent =
  | TextDeltaEvent
  | ToolCallEvent
  | ToolResultEvent
  | ThinkingEvent
  | FinishEvent;

/** Parse a PrismEvent from a JSON object. */
export function parseEvent(obj: Record<string, unknown>): PrismEvent {
  switch (obj.type) {
    case "text_delta":
      return { type: "text_delta", text: String(obj.text ?? "") };
    case "tool_call":
      return {
        type: "tool_call",
        id: String(obj.id ?? ""),
        name: String(obj.name ?? ""),
        arguments: String(obj.arguments ?? ""),
      };
    case "tool_result":
      return {
        type: "tool_result",
        tool_use_id: String(obj.tool_use_id ?? ""),
        content: String(obj.content ?? ""),
        is_error: Boolean(obj.is_error),
      };
    case "thinking":
      return { type: "thinking", text: String(obj.text ?? "") };
    case "finish":
      return { type: "finish", reason: (obj.reason as FinishReason) ?? "stop" };
    default:
      throw new Error(`Unknown event type: ${obj.type}`);
  }
}

/** Parse a JSON string into PrismEvent[]. */
export function parseEvents(jsonStr: string): PrismEvent[] {
  const raw = JSON.parse(jsonStr) as Record<string, unknown>[];
  return raw.map(parseEvent);
}
