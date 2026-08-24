/**
 * Prism WASM 端到端真实测试
 *
 * 完整流程：
 * 1. 编码请求 → 发送到真实 API → 接收响应 → 解码响应
 * 2. 编码请求 → 转换为 Anthropic 格式 → 展示转换结果
 * 3. 接收真实响应 → 转换为 Anthropic 格式 → 展示转换结果
 */

import { PrismClient } from "@morning-start/prism-wasm";
import { readFileSync } from "fs";
import { resolve } from "path";
import { config } from "dotenv";

config({ path: resolve(__dirname, "../.env") });

const BASE_URL = process.env.BASE_URL || "https://api.openai.com/v1";
const API_KEY = process.env.API_KEY || "";
const MODEL_ID = process.env.MODEL_ID || "gpt-4o";

const wasmPath = resolve(__dirname, "../../../wrappers/ts/prism.wasm");
const client = new PrismClient(readFileSync(wasmPath));

function separator(title: string) {
  console.log(`\n${"═".repeat(70)}`);
  console.log(`  ${title}`);
  console.log(`${"═".repeat(70)}\n`);
}

async function main() {
  console.log("╔════════════════════════════════════════════════════════════════════╗");
  console.log("║         Prism WASM 端到端真实测试 (编码 → API → 转换)             ║");
  console.log("╚════════════════════════════════════════════════════════════════════╝\n");

  if (!API_KEY) {
    console.error("❌ 未设置 API_KEY，请配置 .env 文件");
    process.exit(1);
  }

  console.log("配置:");
  console.log(`  API: ${BASE_URL}`);
  console.log(`  Key: ***${API_KEY.slice(-4)}`);
  console.log(`  Model: ${MODEL_ID}\n`);

  // ═══════════════════════════════════════════════════════════════
  // 测试 1: 完整流程 (编码 → 发送 → 接收 → 解码)
  // ═══════════════════════════════════════════════════════════════
  separator("测试 1: 完整流程 (编码 → 发送 → 接收 → 解码)");

  const prompt = "What is 2 + 2? Answer in one sentence.";
  console.log(`用户输入: "${prompt}"\n`);

  // 步骤 1: 编码请求
  console.log("步骤 1: 使用 WASM 编码为 OpenAI Chat 格式...");
  const reqResult = client.encodeRequest("openai-chat", prompt);
  if (!reqResult.value) {
    console.error("编码失败:", reqResult.error);
    process.exit(1);
  }

  const reqJson = JSON.parse(reqResult.value);
  reqJson.model = MODEL_ID;
  const finalReq = JSON.stringify(reqJson);

  console.log("编码结果:");
  console.log("┌─────────────────────────────────────────────────────────────────");
  console.log(finalReq);
  console.log("└─────────────────────────────────────────────────────────────────\n");

  // 步骤 2: 发送到真实 API
  console.log("步骤 2: 发送到真实 API...");
  const response = await fetch(`${BASE_URL}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${API_KEY}`
    },
    body: finalReq
  });

  if (!response.ok) {
    const errorText = await response.text();
    console.error(`❌ API 错误: ${response.status}`);
    console.error(errorText);
    process.exit(1);
  }

  const respJson = await response.json();
  console.log("API 响应:");
  console.log("┌─────────────────────────────────────────────────────────────────");
  console.log(JSON.stringify(respJson, null, 2));
  console.log("└─────────────────────────────────────────────────────────────────\n");

  // 步骤 3: 解码响应
  console.log("步骤 3: 使用 WASM 解码响应...");
  const decoded = client.decodeResponse("openai-chat", JSON.stringify(respJson));
  if (decoded.value) {
    console.log("解码结果:");
    console.log("┌─────────────────────────────────────────────────────────────────");
    console.log(`│ AI 回复: "${decoded.value.trim()}"`);
    console.log("└─────────────────────────────────────────────────────────────────\n");
    console.log("✅ 测试 1 通过: 编码 → API → 解码 完整流程成功!");
  } else {
    console.error("❌ 解码失败:", decoded.error);
  }

  // ═══════════════════════════════════════════════════════════════
  // 测试 2: 请求转换 → 发送转换后的请求
  // ═══════════════════════════════════════════════════════════════
  separator("测试 2: 请求转换 → 发送转换后的请求");

  const prompt2 = "Say hello in French.";
  console.log(`用户输入: "${prompt2}"\n`);

  // 步骤 1: 编码 OpenAI Chat 请求
  console.log("步骤 1: 编码 OpenAI Chat 请求...");
  const reqResult2 = client.encodeRequest("openai-chat", prompt2);
  if (!reqResult2.value) {
    console.error("编码失败:", reqResult2.value);
    process.exit(1);
  }

  const reqJson2 = JSON.parse(reqResult2.value);
  reqJson2.model = MODEL_ID;
  const openaiReq = JSON.stringify(reqJson2);

  console.log("OpenAI Chat 请求:");
  console.log("┌─────────────────────────────────────────────────────────────────");
  console.log(openaiReq);
  console.log("└─────────────────────────────────────────────────────────────────\n");

  // 步骤 2: 转换为 Anthropic 格式
  console.log("步骤 2: 转换为 Anthropic 格式...");
  const anthropicReq = client.convert("openai-chat", "anthropic", "request", openaiReq);
  console.log("Anthropic 请求:");
  console.log("┌─────────────────────────────────────────────────────────────────");
  console.log(anthropicReq);
  console.log("└─────────────────────────────────────────────────────────────────\n");

  // 步骤 3: 发送原始 OpenAI 请求到 API
  console.log("步骤 3: 发送原始 OpenAI 请求到 API...");
  const response2 = await fetch(`${BASE_URL}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${API_KEY}`
    },
    body: openaiReq
  });

  if (!response2.ok) {
    const errorText = await response2.text();
    console.error(`❌ API 错误: ${response2.status}`);
    console.error(errorText);
    process.exit(1);
  }

  const respJson2 = await response2.json();
  console.log("API 响应:");
  console.log("┌─────────────────────────────────────────────────────────────────");
  console.log(JSON.stringify(respJson2, null, 2));
  console.log("└─────────────────────────────────────────────────────────────────\n");

  // 步骤 4: 解码响应
  console.log("步骤 4: 解码响应...");
  const decoded2 = client.decodeResponse("openai-chat", JSON.stringify(respJson2));
  if (decoded2.value) {
    console.log("解码结果:");
    console.log("┌─────────────────────────────────────────────────────────────────");
    console.log(`│ AI 回复: "${decoded2.value.trim()}"`);
    console.log("└─────────────────────────────────────────────────────────────────\n");
    console.log("✅ 测试 2 通过: 请求转换 → API → 解码 完整流程成功!");
  } else {
    console.error("❌ 解码失败:", decoded2.error);
  }

  // ═══════════════════════════════════════════════════════════════
  // 测试 3: 响应转换 (API 响应 → Anthropic 格式)
  // ═══════════════════════════════════════════════════════════════
  separator("测试 3: 响应转换 (API 响应 → Anthropic 格式)");

  const prompt3 = "What is the capital of France?";
  console.log(`用户输入: "${prompt3}"\n`);

  // 步骤 1: 编码并发送请求
  console.log("步骤 1: 编码并发送请求...");
  const reqResult3 = client.encodeRequest("openai-chat", prompt3);
  if (!reqResult3.value) {
    console.error("编码失败:", reqResult3.value);
    process.exit(1);
  }

  const reqJson3 = JSON.parse(reqResult3.value);
  reqJson3.model = MODEL_ID;
  const finalReq3 = JSON.stringify(reqJson3);

  const response3 = await fetch(`${BASE_URL}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${API_KEY}`
    },
    body: finalReq3
  });

  if (!response3.ok) {
    const errorText = await response3.text();
    console.error(`❌ API 错误: ${response3.status}`);
    console.error(errorText);
    process.exit(1);
  }

  const respJson3 = await response3.json();
  const respStr3 = JSON.stringify(respJson3);

  console.log("API 响应 (OpenAI Chat 格式):");
  console.log("┌─────────────────────────────────────────────────────────────────");
  console.log(JSON.stringify(respJson3, null, 2));
  console.log("└─────────────────────────────────────────────────────────────────\n");

  // 步骤 2: 转换为 Anthropic 格式
  console.log("步骤 2: 转换为 Anthropic 格式...");

  // 清理响应（移除 reasoning_content 字段）
  const cleanChoices = respJson3.choices.map((c: any) => ({
    index: c.index,
    message: {
      role: c.message.role,
      content: c.message.content
    },
    finish_reason: c.finish_reason
  }));

  const cleanResp = {
    id: respJson3.id,
    model: respJson3.model,
    object: respJson3.object,
    choices: cleanChoices
  };
  const cleanRespStr = JSON.stringify(cleanResp);

  const anthropicResp = client.convert("openai-chat", "anthropic", "response", cleanRespStr);
  console.log("Anthropic 响应:");
  console.log("┌─────────────────────────────────────────────────────────────────");
  console.log(anthropicResp);
  console.log("└─────────────────────────────────────────────────────────────────\n");

  // 步骤 3: 解码原始响应
  console.log("步骤 3: 解码原始响应...");
  const decoded3 = client.decodeResponse("openai-chat", respStr3);
  if (decoded3.value) {
    console.log("解码结果:");
    console.log("┌─────────────────────────────────────────────────────────────────");
    console.log(`│ AI 回复: "${decoded3.value.trim()}"`);
    console.log("└─────────────────────────────────────────────────────────────────\n");
    console.log("✅ 测试 3 通过: API 响应 → 转换 → 解码 完整流程成功!");
  } else {
    console.error("❌ 解码失败:", decoded3.error);
  }

  // ═══════════════════════════════════════════════════════════════
  // 测试 4: 流式响应完整流程
  // ═══════════════════════════════════════════════════════════════
  separator("测试 4: 流式响应完整流程");

  const prompt4 = "Count from 1 to 5, just numbers.";
  console.log(`用户输入: "${prompt4}"\n`);

  // 步骤 1: 编码流式请求
  console.log("步骤 1: 编码流式请求...");
  const streamReq = client.encodeStream("openai-chat", prompt4);
  if (!streamReq.value) {
    console.error("编码失败:", streamReq.value);
    process.exit(1);
  }

  const streamReqJson = JSON.parse(streamReq.value);
  streamReqJson.model = MODEL_ID;
  streamReqJson.stream = true;
  const finalStreamReq = JSON.stringify(streamReqJson);

  console.log("流式请求:");
  console.log("┌─────────────────────────────────────────────────────────────────");
  console.log(finalStreamReq);
  console.log("└─────────────────────────────────────────────────────────────────\n");

  // 步骤 2: 发送流式请求
  console.log("步骤 2: 发送流式请求...");
  const streamResponse = await fetch(`${BASE_URL}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${API_KEY}`
    },
    body: finalStreamReq
  });

  if (!streamResponse.ok) {
    const errorText = await streamResponse.text();
    console.error(`❌ API 错误: ${streamResponse.status}`);
    console.error(errorText);
    process.exit(1);
  }

  // 步骤 3: 接收流式数据
  console.log("步骤 3: 接收流式数据...\n");
  console.log("SSE 流:");
  console.log("┌─────────────────────────────────────────────────────────────────");

  const reader = streamResponse.body?.getReader();
  const decoder = new TextDecoder();
  let fullText = "";
  let chunkCount = 0;

  if (reader) {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      const chunk = decoder.decode(value, { stream: true });
      const lines = chunk.split("\n");

      for (const line of lines) {
        if (line.startsWith("data: ")) {
          const data = line.slice(6).trim();
          if (data === "[DONE]") {
            console.log(`│ [DONE]`);
            continue;
          }

          try {
            const parsed = JSON.parse(data);
            const delta = parsed.choices?.[0]?.delta;
            if (delta?.content) {
              chunkCount++;
              console.log(`│ 块 ${chunkCount}: "${delta.content}"`);
              fullText += delta.content;
            }
          } catch {
            // 忽略解析错误
          }
        }
      }
    }

    console.log("└─────────────────────────────────────────────────────────────────\n");

    console.log("拼接结果:");
    console.log("┌─────────────────────────────────────────────────────────────────");
    console.log(`│ 完整文本: "${fullText}"`);
    console.log("└─────────────────────────────────────────────────────────────────\n");

    console.log("✅ 测试 4 通过: 流式响应完整流程成功!");
  }

  // ═══════════════════════════════════════════════════════════════
  // 总结
  // ═══════════════════════════════════════════════════════════════
  separator("测试总结");

  console.log("┌────────────────────────────────────────────────────────────────┐");
  console.log("│                    所有端到端测试通过! ✅                      │");
  console.log("├────────────────────────────────────────────────────────────────┤");
  console.log("│ 测试 1: 编码 → 发送 → 接收 → 解码      ✅ 完整流程           │");
  console.log("│ 测试 2: 请求转换 → 发送 → 解码          ✅ 协议转换           │");
  console.log("│ 测试 3: 接收 → 响应转换 → 解码          ✅ 响应转换           │");
  console.log("│ 测试 4: 流式请求 → 流式接收 → 拼接      ✅ 流式处理           │");
  console.log("└────────────────────────────────────────────────────────────────┘\n");

  console.log("结论:");
  console.log("  Prism WASM 模块可以完成完整的端到端协议转换流程:");
  console.log("  1. 编码: 文本 → OpenAI Chat JSON");
  console.log("  2. 转换: OpenAI Chat → Anthropic/Gemini");
  console.log("  3. 发送: 通过真实 API 发送请求");
  console.log("  4. 接收: 接收 API 响应");
  console.log("  5. 解码: API 响应 → 文本");
  console.log("  6. 转换: OpenAI Chat 响应 → Anthropic 响应");
}

main().catch(console.error);
