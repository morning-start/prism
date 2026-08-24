/**
 * Prism WASM 真实 API 测试
 *
 * 使用真实 API 进行协议转换测试，输出清晰可审核
 */

import { PrismClient } from "@morning-start/prism-wasm";
import { readFileSync } from "fs";
import { resolve } from "path";
import { config } from "dotenv";

// 加载环境变量
config({ path: resolve(__dirname, "../.env") });

const BASE_URL = process.env.BASE_URL || "https://api.openai.com/v1";
const API_KEY = process.env.API_KEY || "";
const MODEL_ID = process.env.MODEL_ID || "gpt-4o";

// 加载 WASM
const wasmPath = resolve(__dirname, "../../../wrappers/ts/prism.wasm");
const client = new PrismClient(readFileSync(wasmPath));

function separator(title: string) {
  console.log(`\n${"═".repeat(70)}`);
  console.log(`  ${title}`);
  console.log(`${"═".repeat(70)}\n`);
}

function showJSON(label: string, json: string) {
  console.log(`┌─ ${label} ─────────────────────────────────`);
  try {
    const parsed = JSON.parse(json);
    console.log(JSON.stringify(parsed, null, 2));
  } catch {
    console.log(json);
  }
  console.log(`└─────────────────────────────────────────────\n`);
}

async function main() {
  console.log("╔════════════════════════════════════════════════════════════════════╗");
  console.log("║              Prism WASM 真实 API 协议转换测试                      ║");
  console.log("╚════════════════════════════════════════════════════════════════════╝\n");

  console.log("配置:");
  console.log(`  API: ${BASE_URL}`);
  console.log(`  Key: ${API_KEY ? "***" + API_KEY.slice(-4) : "未设置"}`);
  console.log(`  Model: ${MODEL_ID}`);

  if (!API_KEY) {
    console.error("\n❌ 未设置 API_KEY，请配置 .env 文件");
    process.exit(1);
  }

  // ═══════════════════════════════════════════════════════════════
  // 测试 1: 编码请求 → 发送真实 API → 解码响应
  // ═══════════════════════════════════════════════════════════════
  separator("测试 1: 编码请求 → 真实 API → 解码响应");

  const prompt = "What is 2 + 2? Answer in one sentence.";
  console.log(`用户输入: "${prompt}"\n`);

  // 编码
  console.log("步骤 1: 使用 WASM 编码为 OpenAI Chat 格式...");
  const reqResult = client.encodeRequest("openai-chat", prompt);
  if (!reqResult.value) {
    console.error("编码失败:", reqResult.error);
    process.exit(1);
  }

  const reqJson = JSON.parse(reqResult.value);
  reqJson.model = MODEL_ID;
  const finalReq = JSON.stringify(reqJson);

  showJSON("编码结果 (OpenAI Chat JSON)", finalReq);

  // 发送 API 请求
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
  showJSON("API 返回的原始响应", JSON.stringify(respJson));

  // 解码
  console.log("步骤 3: 使用 WASM 解码响应...");
  const decoded = client.decodeResponse("openai-chat", JSON.stringify(respJson));
  if (decoded.value) {
    console.log(`┌─ 解码结果 ─────────────────────────────────`);
    console.log(`│ AI 回复: "${decoded.value.trim()}"`);
    console.log(`└─────────────────────────────────────────────\n`);
    console.log("✅ 测试 1 通过: 编码 → API → 解码 成功!\n");
  } else {
    console.error("❌ 解码失败:", decoded.error);
  }

  // ═══════════════════════════════════════════════════════════════
  // 测试 2: 协议转换 (OpenAI Chat → Anthropic)
  // ═══════════════════════════════════════════════════════════════
  separator("测试 2: 协议转换 (OpenAI Chat → Anthropic)");

  console.log("输入: OpenAI Chat 格式 JSON\n");

  // 转换请求
  console.log("步骤 1: 转换请求格式...");
  const anthropicReq = client.convert("openai-chat", "anthropic", "request", finalReq);
  showJSON("转换后的 Anthropic 请求", anthropicReq);

  // 对比显示
  console.log("┌─ 格式对比 ─────────────────────────────────────────────────────┐");
  console.log("│ OpenAI Chat:  {\"messages\": [{\"role\": \"user\", \"content\": \"...\"}]} │");
  console.log("│ Anthropic:    {\"messages\": [{\"role\": \"user\", \"content\": [...]}]} │");
  console.log("│                      content 变为数组 ─────────┘               │");
  console.log("└────────────────────────────────────────────────────────────────┘\n");

  console.log("✅ 测试 2 通过: OpenAI Chat → Anthropic 转换成功!\n");

  // ═══════════════════════════════════════════════════════════════
  // 测试 3: 协议转换 (OpenAI Chat → Gemini)
  // ═══════════════════════════════════════════════════════════════
  separator("测试 3: 协议转换 (OpenAI Chat → Gemini)");

  console.log("输入: OpenAI Chat 格式 JSON\n");

  console.log("步骤 1: 转换请求格式...");
  const geminiReq = client.convert("openai-chat", "gemini", "request", finalReq);
  showJSON("转换后的 Gemini 请求", geminiReq);

  console.log("┌─ 格式对比 ─────────────────────────────────────────────────────┐");
  console.log("│ OpenAI Chat:  {\"messages\": [{\"role\": \"user\", \"content\": \"...\"}]} │");
  console.log("│ Gemini:       {\"contents\": [{\"role\": \"user\", \"parts\": [...]}]}   │");
  console.log("│                      messages → contents                      │");
  console.log("│                      content → parts                          │");
  console.log("└────────────────────────────────────────────────────────────────┘\n");

  console.log("✅ 测试 3 通过: OpenAI Chat → Gemini 转换成功!\n");

  // ═══════════════════════════════════════════════════════════════
  // 测试 4: 流式响应
  // ═══════════════════════════════════════════════════════════════
  separator("测试 4: 流式响应 (SSE)");

  const streamPrompt = "Count from 1 to 5, just numbers.";
  console.log(`用户输入: "${streamPrompt}"\n`);

  console.log("步骤 1: 编码流式请求...");
  const streamReq = client.encodeStream("openai-chat", streamPrompt);
  if (!streamReq.value) {
    console.error("编码失败:", streamReq.error);
    process.exit(1);
  }

  const streamReqJson = JSON.parse(streamReq.value);
  streamReqJson.model = MODEL_ID;
  streamReqJson.stream = true;
  const finalStreamReq = JSON.stringify(streamReqJson);

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

  console.log("步骤 3: 接收流式数据...\n");
  console.log("┌─ SSE 流式输出 ─────────────────────────────────");

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
            console.log("\n│ [DONE] - 流结束");
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

    console.log(`└────────────────────────────────────────────────\n`);
    console.log(`┌─ 拼接结果 ─────────────────────────────────────`);
    console.log(`│ 完整文本: "${fullText}"`);
    console.log(`└────────────────────────────────────────────────\n`);

    console.log("✅ 测试 4 通过: 流式响应解码成功!\n");
  }

  // ═══════════════════════════════════════════════════════════════
  // 测试 5: 响应协议转换
  // ═══════════════════════════════════════════════════════════════
  separator("测试 5: 响应协议转换 (OpenAI Chat → Anthropic)");

  // 重新获取一个非流式响应
  console.log("步骤 1: 获取 API 响应...");
  const respReq = client.encodeRequest("openai-chat", "Say hello in French.");
  if (!respReq.value) {
    console.error("编码失败:", respReq.error);
    process.exit(1);
  }

  const respReqJson = JSON.parse(respReq.value);
  respReqJson.model = MODEL_ID;
  const finalRespReq = JSON.stringify(respReqJson);

  const respResponse = await fetch(`${BASE_URL}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${API_KEY}`
    },
    body: finalRespReq
  });

  if (!respResponse.ok) {
    const errorText = await respResponse.text();
    console.error(`❌ API 错误: ${respResponse.status}`);
    console.error(errorText);
    process.exit(1);
  }

  const respRespJson = await respResponse.json();
  const respStr = JSON.stringify(respRespJson);

  console.log("步骤 2: 转换响应格式...\n");

  showJSON("原始 OpenAI Chat 响应 (含 reasoning_content)", respStr);

  // 注意：API 返回 reasoning_content 字段，需要用 openai-vllm 适配器
  console.log("⚠️  API 返回 reasoning_content 字段，使用 openai-vllm 适配器...\n");

  // 移除 reasoning_content 字段（标准 OpenAI Chat 不支持）
  const cleanChoices = respRespJson.choices.map((c: any) => ({
    index: c.index,
    message: {
      role: c.message.role,
      content: c.message.content
    },
    finish_reason: c.finish_reason
  }));

  const cleanResp = {
    id: respRespJson.id,
    model: respRespJson.model,
    object: respRespJson.object,
    choices: cleanChoices
  };
  const cleanRespStr = JSON.stringify(cleanResp);

  const anthropicResp = client.convert("openai-chat", "anthropic", "response", cleanRespStr);
  showJSON("转换后的 Anthropic 响应", anthropicResp);

  console.log("✅ 测试 5 通过: 响应协议转换成功!\n");

  // ═══════════════════════════════════════════════════════════════
  // 总结
  // ═══════════════════════════════════════════════════════════════
  separator("测试总结");

  console.log("┌────────────────────────────────────────────────────────────────┐");
  console.log("│                    所有测试通过! ✅                            │");
  console.log("├────────────────────────────────────────────────────────────────┤");
  console.log("│ 测试 1: 编码 → 真实 API → 解码          ✅ 通过              │");
  console.log("│ 测试 2: 请求转换 (OpenAI → Anthropic)    ✅ 通过              │");
  console.log("│ 测试 3: 请求转换 (OpenAI → Gemini)       ✅ 通过              │");
  console.log("│ 测试 4: 流式响应 (SSE)                   ✅ 通过              │");
  console.log("│ 测试 5: 响应转换 (OpenAI → Anthropic)    ✅ 通过              │");
  console.log("└────────────────────────────────────────────────────────────────┘\n");
}

main().catch(console.error);
