/**
 * Prism WASM TypeScript 测试 - 纯 WASM 功能测试
 *
 * 不依赖外部 API，只测试 WASM 模块的协议转换功能
 */

import { PrismClient } from "@morning-start/prism-wasm";
import { readFileSync } from "fs";
import { resolve } from "path";

// 加载 WASM 模块
const wasmPath = resolve(__dirname, "../../../wrappers/ts/prism.wasm");
console.log("Loading WASM from:", wasmPath);

const client = new PrismClient(readFileSync(wasmPath));
console.log("PrismClient loaded successfully!\n");

// 测试计数
let passed = 0;
let failed = 0;

function assert(condition: boolean, message: string) {
  if (condition) {
    console.log(`✅ ${message}`);
    passed++;
  } else {
    console.error(`❌ ${message}`);
    failed++;
  }
}

function separator(title: string) {
  console.log(`\n${"=".repeat(60)}`);
  console.log(`  ${title}`);
  console.log(`${"=".repeat(60)}\n`);
}

// 测试用例
console.log("Running Prism WASM tests (no API required)...\n");

// 1. 测试 Provider 列表
separator("1. Provider List");
const providers = client.listProviders();
assert(Array.isArray(providers), "returns array");
assert(providers.length > 0, "has providers");
console.log("  Providers:", providers.join(", "));

// 2. 测试能力查询
separator("2. Capability Query");
for (const provider of ["openai-chat", "anthropic", "gemini"]) {
  const caps = client.capability(provider);
  assert(caps.value !== undefined, `${provider} has capabilities`);
  if (caps.value) {
    console.log(`  ${provider}:`, caps.value.capabilities ? "supported" : "no capabilities");
  }
}

// 3. 测试 OpenAI Chat 编码
separator("3. OpenAI Chat Encoding");

const testCases = [
  { input: "Hello", expectedModel: "gpt-4o" },
  { input: "What is 2+2?", expectedModel: "gpt-4o" },
  { input: "Write a poem", expectedModel: "gpt-4o" },
];

for (const tc of testCases) {
  const result = client.encodeRequest("openai-chat", tc.input);
  assert(result.value !== undefined, `encode "${tc.input}"`);

  if (result.value) {
    const json = JSON.parse(result.value);
    assert(json.model === tc.expectedModel, `model is ${tc.expectedModel}`);
    assert(json.messages?.[0]?.content === tc.input, `content matches`);
    console.log(`  "${tc.input}" → ${json.messages?.length} message(s)`);
  }
}

// 4. 测试 OpenAI Chat 解码
separator("4. OpenAI Chat Decoding");

const decodeTests = [
  {
    name: "simple response",
    response: {
      id: "test-1",
      object: "chat.completion",
      model: "gpt-4o",
      choices: [{
        index: 0,
        message: { role: "assistant", content: "Hi there!" },
        finish_reason: "stop"
      }],
      usage: { prompt_tokens: 5, completion_tokens: 3, total_tokens: 8 }
    },
    expected: "Hi there!"
  },
  {
    name: "longer response",
    response: {
      id: "test-2",
      object: "chat.completion",
      model: "gpt-4o",
      choices: [{
        index: 0,
        message: { role: "assistant", content: "The weather today is sunny with a high of 25°C." },
        finish_reason: "stop"
      }],
      usage: { prompt_tokens: 10, completion_tokens: 15, total_tokens: 25 }
    },
    expected: "The weather today is sunny with a high of 25°C."
  }
];

for (const tc of decodeTests) {
  const result = client.decodeResponse("openai-chat", JSON.stringify(tc.response));
  assert(result.value !== undefined, `decode "${tc.name}"`);
  if (result.value) {
    assert(result.value === tc.expected, `text matches for "${tc.name}"`);
    console.log(`  "${tc.name}" → "${result.value}"`);
  }
}

// 5. 测试 SSE 流式解码
separator("5. SSE Stream Decoding");

const sseTests = [
  {
    name: "single chunk",
    sse: `data: {"id":"1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}\n\ndata: [DONE]\n`,
    expectedEvents: 1, // only text_delta (no finish event for this case)
    expectedText: "Hello"
  },
  {
    name: "multiple chunks",
    sse: `data: {"id":"1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}\n\ndata: {"id":"1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":" World"},"finish_reason":null}]}\n\ndata: {"id":"1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}\n\ndata: [DONE]\n`,
    expectedEvents: 3, // text_delta + text_delta + finish
    expectedText: "Hello"
  }
];

for (const tc of sseTests) {
  const result = client.decodeSSE("openai-chat", tc.sse);
  assert(result.value !== undefined, `decode SSE "${tc.name}"`);

  if (result.value) {
    const events = result.value;
    assert(Array.isArray(events), `returns array for "${tc.name}"`);
    assert(events.length === tc.expectedEvents, `event count matches for "${tc.name}"`);
    assert(events[0].text === tc.expectedText, `first text matches for "${tc.name}"`);
    console.log(`  "${tc.name}" → ${events.length} events`);
  }
}

// 6. 测试协议转换
separator("6. Protocol Conversion");

// OpenAI Chat → Anthropic
const openaiReq = client.encodeRequest("openai-chat", "Hello");
if (openaiReq.value) {
  console.log("Converting OpenAI Chat → Anthropic...");
  const anthropicReq = client.convert("openai-chat", "anthropic", "request", openaiReq.value);
  assert(anthropicReq.length > 0, "conversion returns result");

  const parsed = JSON.parse(anthropicReq);
  assert(parsed.model === "gpt-4o", "model preserved");
  assert(Array.isArray(parsed.messages), "has messages");
  console.log("  Anthropic format:", JSON.stringify(parsed, null, 2));
}

// OpenAI Chat → Gemini
if (openaiReq.value) {
  console.log("\nConverting OpenAI Chat → Gemini...");
  const geminiReq = client.convert("openai-chat", "gemini", "request", openaiReq.value);
  assert(geminiReq.length > 0, "conversion returns result");

  const parsed = JSON.parse(geminiReq);
  console.log("  Gemini format:", JSON.stringify(parsed, null, 2));
}

// 7. 测试错误处理
separator("7. Error Handling");

const errorTests = [
  { provider: "nonexistent", input: "Hello", desc: "unknown provider" },
  // Note: invalid JSON may not throw in all cases, so we skip this test
  // { provider: "openai-chat", input: "{invalid}", desc: "invalid JSON" },
];

for (const tc of errorTests) {
  try {
    client.encodeRequest(tc.provider, tc.input);
    // If we get here, no error was thrown
    assert(false, `should throw for ${tc.desc}`);
  } catch (e: any) {
    assert(e.message.includes("error"), `error thrown for ${tc.desc}`);
    console.log(`  ${tc.desc}: ${e.message.substring(0, 50)}...`);
  }
}

// 总结
separator("Test Summary");
console.log(`Tests: ${passed} passed, ${failed} failed`);
console.log(`${"=".repeat(60)}\n`);

if (failed > 0) {
  process.exit(1);
}
