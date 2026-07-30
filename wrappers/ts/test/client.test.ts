/** Tests for the Prism WASM TypeScript wrapper. */

import { describe, expect, test } from "bun:test";
import { PrismClient, parseEvents } from "../src/index.ts";
import { readFileSync } from "fs";
import { resolve } from "path";

const wasmPath = resolve(import.meta.dir, "../prism.wasm");
const wasmBytes = readFileSync(wasmPath);
const hasWasm = wasmBytes.length > 100;

describe("PrismClient", () => {
  test("constructor loads prism.wasm", () => {
    if (!hasWasm) return; // skip if no wasm file
    const client = new PrismClient(wasmBytes);
    expect(client).toBeDefined();
  });

  test("listProviders returns known providers", () => {
    if (!hasWasm) return;
    const client = new PrismClient(wasmBytes);
    const providers = client.listProviders();
    expect(providers).toContain("openai");
    expect(providers).toContain("anthropic");
  });

  test("ping returns pong", () => {
    if (!hasWasm) return;
    const client = new PrismClient(wasmBytes);
    expect(client.ping()).toBe("pong");
  });
});

describe("parseEvents", () => {
  test("parses text delta event", () => {
    const json = JSON.stringify([{ type: "text_delta", text: "你好" }]);
    const events = parseEvents(json);
    expect(events).toHaveLength(1);
    expect(events[0].type).toBe("text_delta");
    if (events[0].type === "text_delta") {
      expect(events[0].text).toBe("你好");
    }
  });

  test("parses finish event", () => {
    const json = JSON.stringify([{ type: "finish", reason: "stop" }]);
    const events = parseEvents(json);
    expect(events).toHaveLength(1);
    expect(events[0].type).toBe("finish");
    if (events[0].type === "finish") {
      expect(events[0].reason).toBe("stop");
    }
  });

  test("parses multiple events", () => {
    const json = JSON.stringify([
      { type: "text_delta", text: "Hello" },
      { type: "finish", reason: "stop" },
    ]);
    const events = parseEvents(json);
    expect(events).toHaveLength(2);
    expect(events[0].type).toBe("text_delta");
    expect(events[1].type).toBe("finish");
  });

  test("throws on unknown event type", () => {
    const json = JSON.stringify([{ type: "unknown_event" }]);
    expect(() => parseEvents(json)).toThrow("Unknown event type");
  });
});
