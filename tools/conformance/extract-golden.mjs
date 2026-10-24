/**
 * 从 vendored 官方 OpenAPI 抽取真实样本 → fixtures/golden/*.json
 *
 * 为什么从这里抽：仓库已 vendored `schemas/endpoints/openai-openapi.yaml`
 * （官方仓库，MIT），内嵌大量真实响应体与 SSE 流。零成本、离线、无 license 风险。
 *
 * 三类样本来源（都要处理，否则会漏）：
 *   1. `data: {...}` 行      —— SSE 帧（Responses / Assistants 流）
 *   2. 裸 JSON 行 `{"object":...}` —— Chat Completions chunk 示例（无 data: 前缀）
 *   3. `example: |` 块里的完整响应体
 *
 * 用法：node extract-golden.mjs
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import YAML from 'yaml';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '..', '..');
const OUT = path.join(REPO, 'fixtures/golden');

const spec = YAML.parse(
  fs.readFileSync(path.join(REPO, 'schemas/endpoints/openai-openapi.yaml'), 'utf8'),
);

// 收集所有字符串节点
const strings = [];
const walk = (o) => {
  if (typeof o === 'string') { strings.push(o); return; }
  if (Array.isArray(o)) return o.forEach(walk);
  if (o && typeof o === 'object') for (const v of Object.values(o)) walk(v);
};
walk(spec);
console.log(`扫描 ${strings.length} 个字符串节点`);

/** 从任意文本里捞出所有 JSON 对象（逐行尝试，兼顾 data: 前缀与裸 JSON） */
function harvest(text) {
  const out = [];
  for (const rawLine of text.split('\n')) {
    let line = rawLine.trim();
    if (line.startsWith('data:')) line = line.slice(5).trim();
    if (!line.startsWith('{')) continue;
    try { out.push(JSON.parse(line)); } catch { /* 半截或多行，跳过 */ }
  }
  return out;
}

fs.mkdirSync(OUT, { recursive: true });
// 清掉旧产物，避免上次残留影响结果
for (const f of fs.readdirSync(OUT)) {
  if (f.endsWith('.json')) fs.unlinkSync(path.join(OUT, f));
}

const written = { responses: 0, chunk: 0, message: 0 };
const seen = new Set();
function emit(name, doc) {
  const file = path.join(OUT, name);
  if (seen.has(file)) return;
  seen.add(file);
  fs.writeFileSync(file, JSON.stringify(doc, null, 2) + '\n', 'utf8');
}

for (const s of strings) {
  for (const j of harvest(s)) {
    // ── Chat Completions chunk ──
    if (j.object === 'chat.completion.chunk') {
      const fr = j.choices?.[0]?.finish_reason ?? null;
      const deltaKeys = Object.keys(j.choices?.[0]?.delta ?? {}).sort().join(',');
      const key = `chunk|${fr}|${deltaKeys}`;
      if (seen.has(key)) continue;
      seen.add(key);
      const slug = (fr ?? 'null') + '-' + (deltaKeys || 'empty').replace(/,/g, '-');
      written.chunk++;
      emit(`openai-chunk-${String(written.chunk).padStart(2, '0')}-${slug}.json`, {
        desc: `官方 spec 内嵌真实 chunk：finish_reason=${fr ?? 'null'}，delta={${deltaKeys}}`,
        schema: 'openai-chat-chunk.json',
        payload: j,
        expect: true,
      });
    }

    // ── Anthropic Message（若 spec 里出现）──
    if (j.type === 'message' && j.stop_reason !== undefined && j.id) {
      const key = `msg|${j.stop_reason}|${j.stop_sequence}`;
      if (seen.has(key)) continue;
      seen.add(key);
      written.message++;
      emit(`anthropic-message-${String(written.message).padStart(2, '0')}.json`, {
        desc: `官方 spec 内嵌真实 message（stop_reason=${j.stop_reason}）`,
        schema: 'anthropic-message.json',
        payload: j,
        expect: true,
      });
    }

    // ── Responses 终止事件的 response 体 ──
    for (const term of ['completed', 'incomplete', 'failed']) {
      if (j.type === `response.${term}` && j.response) {
        const key = `resp|${term}`;
        if (seen.has(key)) continue;
        seen.add(key);
        written.responses++;
        emit(`responses-${term}.json`, {
          desc: `官方 spec 内嵌真实 response.${term} 事件的 response 体`,
          schema: 'openai-responses-response.json',
          payload: j.response,
          expect: true,
        });
      }
    }
  }
}

console.log('写出:');
for (const [k, v] of Object.entries(written)) console.log(`  ${k}: ${v}`);
console.log('总计:', Object.values(written).reduce((a, b) => a + b, 0));
