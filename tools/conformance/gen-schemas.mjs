/**
 * 从官方 SDK 的 TS 类型生成 JSON Schema，并抽取权威枚举。
 *
 * 为什么是 TS 而不是 Go/Python：
 *   - Go SDK 把枚举定义成 `type X string` + 常量，反射只能得到 {"type":"string"}，
 *     枚举约束完全丢失（实测）。无法用于校验。
 *   - TS 的 Literal 联合与 enum 都能被 ts-json-schema-generator 转成真正的
 *     JSON Schema `enum`，这是能校验"值是否合法"的前提。
 *
 * 产物入库（tools/conformance/schemas/），这样升级 SDK 后的枚举变化会体现在
 * git diff 里 —— 把"人工保证白名单"换成"版本化事实"。
 *
 * 用法：node gen-schemas.mjs
 */
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.join(HERE, 'schemas');
const MODULES = path.join(HERE, 'node_modules');
const REPO = path.resolve(HERE, '..', '..');

fs.mkdirSync(OUT, { recursive: true });

/** ts-json-schema-generator 的封装：把一个 d.ts 里的类型转成 JSON Schema 文件 */
function gen(name, dtsPath, typeName) {
  const outFile = path.join(OUT, name);
  const bin = path.join(MODULES, '.bin', process.platform === 'win32' ? 'ts-json-schema-generator.cmd' : 'ts-json-schema-generator');
  try {
    execFileSync(bin, [
      '--path', dtsPath,
      '--type', typeName,
      '--out', outFile,
      '--no-type-check',
    ], { stdio: 'pipe', shell: process.platform === 'win32' });
    const sz = fs.statSync(outFile).size;
    console.log(`  ok  ${name}  (${sz} bytes)`);
    return JSON.parse(fs.readFileSync(outFile, 'utf8'));
  } catch (e) {
    console.error(`  FAIL ${name}: ${String(e.stderr || e.message).slice(0, 300)}`);
    return null;
  }
}

console.log('generating JSON Schemas from official SDKs...');
const schemas = {};

// --- Anthropic Messages ---
schemas.anthropicMessage = gen(
  'anthropic-message.json',
  path.join(MODULES, '@anthropic-ai/sdk/resources/messages/messages.d.ts'),
  'Message',
);
schemas.anthropicStream = gen(
  'anthropic-stream-event.json',
  path.join(MODULES, '@anthropic-ai/sdk/resources/messages/messages.d.ts'),
  'RawMessageStreamEvent',
);

// --- OpenAI Chat Completions ---
schemas.openaiChunk = gen(
  'openai-chat-chunk.json',
  path.join(MODULES, 'openai/resources/chat/completions/completions.d.ts'),
  'ChatCompletionChunk',
);
schemas.openaiResponse = gen(
  'openai-chat-response.json',
  path.join(MODULES, 'openai/resources/chat/completions/completions.d.ts'),
  'ChatCompletion',
);
// Responses API 的终止事件里带的是完整 Response 对象
schemas.openaiResponses = gen(
  'openai-responses-response.json',
  path.join(MODULES, 'openai/resources/responses/responses.d.ts'),
  'Response',
);

// --- Gemini ---
schemas.geminiCandidate = gen(
  'gemini-candidate.json',
  path.join(MODULES, '@google/genai/dist/genai.d.ts'),
  'Candidate',
);

/**
 * 抽取三家权威枚举。
 *
 * OpenAI 从已 vendored 的官方 OpenAPI 取（仓库里那份，MIT）；
 * Anthropic / Gemini 从生成的 schema 的 definitions 里取。
 */
console.log('extracting literal sets...');

function enumFromDefs(schema, defName) {
  const d = schema?.definitions?.[defName];
  return Array.isArray(d?.enum) ? d.enum.filter((x) => x !== null) : null;
}

const YAML = (await import('yaml')).default;
const openapi = YAML.parse(
  fs.readFileSync(path.join(REPO, 'schemas/endpoints/openai-openapi.yaml'), 'utf8'),
);
const openaiFinish = openapi?.components?.schemas?.CreateChatCompletionStreamResponse
  ?.properties?.choices?.items?.properties?.finish_reason?.enum ?? null;

const authority = {
  _generated: new Date().toISOString().slice(0, 10),
  _sources: {
    'messages.stop_reason': '@anthropic-ai/sdk (Message.stop_reason -> StopReason)',
    'openai.finish_reason': 'schemas/endpoints/openai-openapi.yaml (vendored, MIT)',
    'gemini.finishReason': '@google/genai (FinishReason enum)',
  },
  'messages.stop_reason': enumFromDefs(schemas.anthropicMessage, 'StopReason'),
  'openai.finish_reason': openaiFinish,
  'gemini.finishReason': enumFromDefs(schemas.geminiCandidate, 'FinishReason'),
};

// OpenAI 的 finish_reason 也带 null（流式首帧允许 null），抽出非 null 值
if (Array.isArray(authority['openai.finish_reason'])) {
  authority['openai.finish_reason'] = authority['openai.finish_reason'].filter((x) => x !== null);
}

fs.writeFileSync(
  path.join(OUT, 'authority.json'),
  JSON.stringify(authority, null, 2) + '\n',
  'utf8',
);

console.log('\nauthority.json:');
for (const k of ['messages.stop_reason', 'openai.finish_reason', 'gemini.finishReason']) {
  const v = authority[k];
  console.log(`  ${k}: ${v ? v.length + ' values' : 'MISSING'}`);
}
if (!authority['messages.stop_reason'] || !authority['openai.finish_reason'] || !authority['gemini.finishReason']) {
  console.error('\nERROR: 至少一处权威枚举抽取失败，不能静默通过。');
  process.exit(1);
}
console.log('\ndone.');
