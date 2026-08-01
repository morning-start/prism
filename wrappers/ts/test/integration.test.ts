/**
 * End-to-end integration test for the Prism WASM wrapper.
 *
 * Requires a classic-wasm build of the export shim:
 *   moon build --target wasm
 *   node --experimental-strip-types test/integration.test.ts
 */
import { strict as assert } from "node:assert";
import { loadWasm, callWasm, PrismError } from "../src/wasm.ts";

import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const TEST_DIR = dirname(fileURLToPath(import.meta.url));
const WASM_PATH =
  process.env.PRISM_WASM ??
  resolve(TEST_DIR, "../../../_build/wasm/debug/build/cmd/main/main.wasm");

loadWasm(WASM_PATH);

const CHAT_RESPONSE = JSON.stringify({
  id: "1",
  object: "chat.completion",
  model: "gpt-4o",
  choices: [
    {
      index: 0,
      message: { role: "assistant", content: "Hi" },
      finish_reason: "stop",
    },
  ],
});

// 1. Capability returns the full declaration, not just the provider name.
const cap = JSON.parse(callWasm("wasm_sdk_capability", "openai"));
assert.equal(cap.provider, "openai");
assert.ok("model_pattern" in cap);
assert.ok("capabilities" in cap);

// 2. Request encoding produces OpenAI Responses JSON.
const req = JSON.parse(callWasm("wasm_sdk_encode_req", "openai", "Hello"));
assert.equal(req.model, "gpt-4o");
assert.equal(req.input[0].type, "message");
assert.equal(req.input[0].content[0].text, "Hello");

// 3. Response decoding extracts the text.
assert.equal(
  callWasm("wasm_sdk_decode_resp", "openai-chat", CHAT_RESPONSE),
  "Hi"
);

// 4. SSE decoding produces an event array.
const events = JSON.parse(
  callWasm(
    "wasm_sdk_decode_sse",
    "openai-chat",
    'data: {"id":"1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"Hi"},"finish_reason":null}]}\n\ndata: [DONE]\n'
  )
);
assert.equal(events[0].type, "text_delta");
assert.equal(events[0].text, "Hi");

// 5. Unicode, quotes and newlines survive the UTF-16 marshalling.
const uni = JSON.parse(
  callWasm("wasm_sdk_encode_req", "openai", '你好"引号\n换行')
);
assert.equal(uni.input[0].content[0].text, '你好"引号\n换行');

// 6. Unknown provider surfaces as a PrismError with a stable prefix.
assert.throws(
  () => callWasm("wasm_sdk_capability", "no-such-provider"),
  (e: unknown) => e instanceof PrismError && (e as PrismError).message.includes("unknown provider")
);

console.log("all integration tests passed");
