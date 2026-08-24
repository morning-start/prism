/**
 * Prism WASM TypeScript 测试 - 使用环境变量配置
 *
 * 测试内容：
 * 1. WASM 模块加载和基本功能
 * 2. OpenAI Chat 协议编码/解码
 * 3. 与真实 API 的集成测试（使用 .env 配置）
 */

import { PrismClient } from "@morning-start/prism-wasm";
import { readFileSync } from "fs";
import { resolve } from "path";
import { config } from "dotenv";

// 加载环境变量
config({ path: resolve(__dirname, "../.env") });

// 测试配置
const BASE_URL = process.env.BASE_URL || "https://api.openai.com/v1";
const API_KEY = process.env.API_KEY || "";
const MODEL_ID = process.env.MODEL_ID || "gpt-4o";
const DEBUG = process.env.DEBUG === "true";

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
console.log("Running Prism WASM tests with environment configuration...\n");
console.log("Configuration:");
console.log(`  BASE_URL: ${BASE_URL}`);
console.log(`  API_KEY: ${API_KEY ? "***" + API_KEY.slice(-4) : "not set"}`);
console.log(`  MODEL_ID: ${MODEL_ID}`);
console.log(`  DEBUG: ${DEBUG}\n`);

// 1. 测试 WASM 基本功能
separator("1. WASM Basic Functions");

console.log("Testing listProviders...");
const providers = client.listProviders();
assert(Array.isArray(providers), "listProviders returns array");
assert(providers.includes("openai-chat"), "includes openai-chat");
assert(providers.includes("anthropic"), "includes anthropic");
console.log("  Available providers:", providers.join(", "));

console.log("\nTesting capability...");
const caps = client.capability("openai-chat");
assert(caps.value !== undefined, "capability returns value");
if (caps.value) {
  console.log("  OpenAI Chat capabilities:", JSON.stringify(caps.value, null, 2));
}

// 2. 测试 OpenAI Chat 协议编码
separator("2. OpenAI Chat Protocol Encoding");

console.log("Testing encodeRequest...");
const testMessage = "Hello, how are you?";
const encodeResult = client.encodeRequest("openai-chat", testMessage);
assert(encodeResult.value !== undefined, "encodeRequest returns value");

if (encodeResult.value) {
  const reqJson = JSON.parse(encodeResult.value);
  console.log("  Generated JSON:");
  console.log("    model:", reqJson.model);
  console.log("    messages:", reqJson.messages?.length);
  console.log("    content:", reqJson.messages?.[0]?.content);
  assert(reqJson.model === "gpt-4o", "default model is gpt-4o");
  assert(reqJson.messages?.length === 1, "has one message");
  assert(reqJson.messages?.[0]?.role === "user", "role is user");
  assert(reqJson.messages?.[0]?.content === testMessage, "content matches");
}

// 3. 测试 OpenAI Chat 协议解码
separator("3. OpenAI Chat Protocol Decoding");

const mockResponse = JSON.stringify({
  id: "chatcmpl-test-123",
  object: "chat.completion",
  model: "gpt-4o",
  choices: [{
    index: 0,
    message: {
      role: "assistant",
      content: "I'm doing well, thank you for asking!"
    },
    finish_reason: "stop"
  }],
  usage: {
    prompt_tokens: 10,
    completion_tokens: 15,
    total_tokens: 25
  }
});

console.log("Testing decodeResponse...");
const decodeResult = client.decodeResponse("openai-chat", mockResponse);
assert(decodeResult.value !== undefined, "decodeResponse returns value");
if (decodeResult.value) {
  console.log("  Decoded text:", decodeResult.value);
  assert(decodeResult.value === "I'm doing well, thank you for asking!", "text matches");
}

// 4. 测试流式解码
separator("4. SSE Stream Decoding");

const mockSSE = `data: {"id":"1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}

data: {"id":"1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}

data: {"id":"1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":" World"},"finish_reason":null}]}

data: {"id":"1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]
`;

console.log("Testing decodeSSE...");
const sseResult = client.decodeSSE("openai-chat", mockSSE);
assert(sseResult.value !== undefined, "decodeSSE returns value");

if (sseResult.value) {
  const events = sseResult.value;
  assert(Array.isArray(events), "returns event array");
  console.log("  Decoded events:", events.length);
  events.forEach((event: any, i: number) => {
    console.log(`    Event ${i}: ${event.type} ${event.text || event.reason || ""}`);
  });
  assert(events.length >= 3, "has at least 3 events");
  assert(events[0].type === "text_delta", "first event is text_delta");
  assert(events[0].text === "Hello", "first text is Hello");
}

// 5. 测试协议转换
separator("5. Protocol Conversion (OpenAI Chat → Anthropic)");

if (encodeResult.value) {
  console.log("Testing convert (request)...");
  const convertResult = client.convert("openai-chat", "anthropic", "request", encodeResult.value);
  assert(convertResult.length > 0, "convert returns non-empty result");

  const anthropicReq = JSON.parse(convertResult);
  console.log("  Anthropic request:");
  console.log("    model:", anthropicReq.model);
  console.log("    messages:", anthropicReq.messages?.length);
  console.log("    max_tokens:", anthropicReq.max_tokens);
  assert(anthropicReq.model === "gpt-4o", "model preserved");
  assert(Array.isArray(anthropicReq.messages), "has messages array");
}

// 6. 测试真实 API 调用（如果配置了 API Key）
separator("6. Real API Integration Test");

if (!API_KEY) {
  console.log("⚠️  API_KEY not set, skipping real API test");
  console.log("   Set API_KEY in .env to enable integration tests");
} else {
  console.log("Testing real API call...");

  // 编码请求
  const req = client.encodeRequest("openai-chat", "Say 'Hello from Prism!' in one sentence.");
  if (!req.value) {
    console.error("Failed to encode request:", req.error);
  } else {
    // 替换模型 ID
    const reqJson = JSON.parse(req.value);
    reqJson.model = MODEL_ID;
    const finalReq = JSON.stringify(reqJson);

    console.log("  Request encoded successfully");
    console.log("  Using model:", MODEL_ID);

    // 发送真实 API 请求
    try {
      const response = await fetch(`${BASE_URL}/chat/completions`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${API_KEY}`
        },
        body: finalReq
      });

      if (!response.ok) {
        console.error(`  API error: ${response.status} ${response.statusText}`);
        const errorText = await response.text();
        console.error("  Response:", errorText);
      } else {
        const respJson = await response.json();
        console.log("  API response received");

        // 解码响应
        const decoded = client.decodeResponse("openai-chat", JSON.stringify(respJson));
        if (decoded.value) {
          console.log("  Decoded response:", decoded.value);
          assert(decoded.value.length > 0, "response has content");
        } else {
          console.error("  Failed to decode response:", decoded.error);
        }
      }
    } catch (e: any) {
      console.error("  API call failed:", e.message);
    }
  }
}

// 总结
separator("Test Summary");
console.log(`Tests: ${passed} passed, ${failed} failed`);
console.log(`${"=".repeat(60)}\n`);

if (failed > 0) {
  process.exit(1);
}
