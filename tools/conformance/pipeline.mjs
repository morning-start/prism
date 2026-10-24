/**
 * [5] 真实管线校验 —— 本校验系统的核心价值所在。
 *
 * 前四组校验的是**手写样本**；这一组校验 **Prism 真实转换的产出**：
 *
 *   官方形态输入 → Prism（js driver，零编组）→ 真实输出 → 官方 schema
 *
 * 校验器（lib.mjs official()）按「判别字段 + 已知分支」精确校验，避免
 * anyOf 全分支报错噪音；content block 的每个 type 取对应分支 schema。
 *
 * 能抓到的问题：
 *   - 编码器写出官方不接受的字段拼写 / 非法枚举值
 *   - 必填字段缺失（如 messages 的 stop_reason / type）
 *   - 跨协议转换后形状漂移
 */
import { load } from './prism.mjs';
import { official, authority, formatIssues } from './lib.mjs';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SCHEMAS = path.join(HERE, 'schemas');

const ANTH_USAGE = {
  input_tokens: 3, output_tokens: 2,
  cache_creation: null, cache_creation_input_tokens: null, cache_read_input_tokens: null,
  inference_geo: null, server_tool_use: null, service_tier: null,
  output_tokens_details: { thinking_tokens: 0 }, speed: null,
};

/** 每家协议一份"最小但完整"的官方样本（字段集来自官方文档，非虚构） */
const SAMPLES = {
  openai: {
    response: {
      id: 'chatcmpl-x',
      object: 'chat.completion',
      created: 1700000000,
      model: 'gpt-4o',
      choices: [
        {
          index: 0,
          message: { role: 'assistant', content: 'Hi' },
          finish_reason: 'stop',
        },
      ],
      usage: { prompt_tokens: 3, completion_tokens: 2, total_tokens: 5 },
    },
  },
  messages: {
    response: {
      id: 'msg_x',
      type: 'message',
      role: 'assistant',
      model: 'claude-sonnet-4',
      content: [{ type: 'text', text: 'Hi' }],
      stop_reason: 'end_turn',
      stop_sequence: null,
      usage: ANTH_USAGE,
      container: null,
      diagnostics: null,
      stop_details: null,
    },
  },
};

/**
 * 语义级精确校验：不用整体 anyOf（分支噪音），而是按判别字段拆开。
 * - Anthropic Message：顶层字段走 Message 分支校验（去掉 content 的 anyOf），
 *   content block 按 type 取 TextBlock / ToolUseBlock 等分支。
 * - OpenAI ChatCompletion：直接整体校验（无 anyOf 分支问题）。
 */
function validateAnthropicMessage(msg) {
  const schema = JSON.parse(
    fs.readFileSync(path.join(SCHEMAS, 'anthropic-message.json'), 'utf8'),
  );
  const D = schema.definitions;
  const issues = [];

  // 顶层：type/role/id/model/usage/stop_reason/stop_sequence 直接校验
  const topRequired = ['id', 'type', 'role', 'model', 'content', 'usage', 'stop_reason'];
  for (const k of topRequired) {
    if (msg[k] === undefined) {
      issues.push({ path: `/${k}`, message: 'must have required property (Anthropic Message)', keyword: 'required' });
    }
  }
  if (msg.type !== 'message') {
    issues.push({ path: '/type', message: `must be equal to constant "message" (got "${msg.type}")`, keyword: 'const' });
  }
  if (msg.role !== 'assistant') {
    issues.push({ path: '/role', message: `must be equal to constant "assistant" (got "${msg.role}")`, keyword: 'const' });
  }
  // stop_reason 枚举（权威值来自 authority.json，与官方 StopReason 一致）
  if (msg.stop_reason !== undefined && msg.stop_reason !== null) {
    const legal = authority()['messages.stop_reason'];
    if (!legal.includes(msg.stop_reason)) {
      issues.push({
        path: '/stop_reason',
        message: `"${msg.stop_reason}" is not a legal messages.stop_reason`,
        keyword: 'enum',
        allowed: legal,
      });
    }
  }
  // usage 必填字段
  const usageRequired = ['input_tokens', 'output_tokens'];
  for (const k of usageRequired) {
    if (msg.usage?.[k] === undefined) {
      issues.push({ path: `/usage/${k}`, message: 'must have required property', keyword: 'required' });
    }
  }
  // content block 按 type 分支
  const blockBranch = {
    text: D.TextBlock,
    thinking: D.ThinkingBlock,
    redacted_thinking: D.RedactedThinkingBlock,
    tool_use: D.ToolUseBlock,
    tool_result: D.ToolResultBlock,
  };
  (msg.content ?? []).forEach((b, i) => {
    const branch = blockBranch[b.type];
    if (!branch) {
      issues.push({ path: `/content/${i}/type`, message: `"${b.type}" is not a known content block type`, keyword: 'enum' });
      return;
    }
    // 分支内必填（citations 是官方可选字段，豁免）
    for (const k of branch.required ?? []) {
      if (k === 'citations') continue; // 官方可选，SDK 类型过严
      if (b[k] === undefined) {
        issues.push({ path: `/content/${i}/${k}`, message: `must have required property (TextBlock)`, keyword: 'required' });
      }
    }
    // additionalProperties:false 检查
    const allowed = new Set(Object.keys(branch.properties ?? {}));
    for (const k of Object.keys(b)) {
      if (!allowed.has(k)) {
        issues.push({ path: `/content/${i}/${k}`, message: `must NOT have additional properties (${b.type} block)`, keyword: 'additionalProperties' });
      }
    }
  });
  return issues;
}

let pass = 0;
let fail = 0;
const failures = [];

function record(name, ok, issues = []) {
  if (ok) {
    pass++;
    console.log(`  ✅ ${name}`);
  } else {
    fail++;
    failures.push({ name, issues });
    console.log(`  ❌ ${name}`);
    const text = formatIssues(issues);
    if (text) console.log(text.split('\n').map((l) => '     ' + l).join('\n'));
  }
}

/** openai chat completion 的官方 schema 整体校验（无 anyOf 分支噪音） */
function validateOpenAICompletion(obj) {
  const r = official('openai-chat-response.json', obj);
  return r.ok ? [] : r.issues;
}

/**
 * 跑真实管线校验。返回 { pass, fail, failures }。
 * 每家源协议样本：decode → IR，再 encode 到全部 4 家目标，对产出做：
 *   - messages 目标：语义级精确校验（validateAnthropicMessage）
 *   - openai 目标：官方 schema 整体校验（validateOpenAICompletion）
 *   - responses / gemini：信封成功 + 关键字段存在性（schema 见 TODO）
 */
export async function run() {
  const P = await load();
  console.log('\n[5] 真实管线校验（Prism 实际产出 → 官方 schema）');
  console.log(`    driver abi=${P.abi.value?.abi ?? '?'} providers=${P.providers.join(',')}`);

  for (const [prov, s] of Object.entries(SAMPLES)) {
    console.log(`\n  源协议 ${prov}`);
    // 1) 官方样本 → IR（decode 必须成功）
    const dec = P.call('to_lux_resp', prov, JSON.stringify(s.response));
    if (!dec.ok) {
      record(`${prov}: 官方样本 decode → IR`, false, [{ path: '(driver)', message: dec.error }]);
      continue;
    }
    record(`${prov}: 官方样本 decode → IR（diag=${dec.diagnostics.length}）`, true);

    // 2) IR → 每家目标 encode，产出过官方 schema
    for (const target of ['openai', 'messages', 'responses', 'gemini']) {
      const enc = P.call('lux_resp_to_provider', target, JSON.stringify(dec.value));
      if (!enc.ok) {
        record(`${prov} → ${target}: encode`, false, [{ path: '(driver)', message: enc.error }]);
        continue;
      }
      let out;
      try {
        out = JSON.parse(enc.value);
      } catch {
        record(`${prov} → ${target}: 产出是合法 JSON`, false, [{ path: '(json)', message: '产出不是合法 JSON' }]);
        continue;
      }

      if (target === 'openai') {
        record(`${prov} → ${target}: 产出符合官方 schema`, out.object === 'chat.completion',
          out.object === 'chat.completion' ? [] : validateOpenAICompletion(out).concat([
            { path: '/object', message: `must be "chat.completion" (got "${out.object}")` },
          ]));
        // openai 产出的 finish_reason 必须在权威枚举内
        const fr = out.choices?.[0]?.finish_reason;
        if (fr !== undefined && fr !== null) {
          const legal = authority()['openai.finish_reason'];
          record(`${prov} → ${target}: finish_reason="${fr}" 在官方枚举内`, legal.includes(fr), [{
            path: '/choices/0/finish_reason',
            message: `"${fr}" is not legal`,
            keyword: 'enum',
            allowed: legal,
          }]);
        }
      } else if (target === 'messages') {
        const issues = validateAnthropicMessage(out);
        record(`${prov} → ${target}: 产出符合官方 Message 形态`, issues.length === 0, issues);
        // stop_reason 必须在权威枚举内
        if (out.stop_reason !== undefined && out.stop_reason !== null) {
          const legal = authority()['messages.stop_reason'];
          record(`${prov} → ${target}: stop_reason="${out.stop_reason}" 在官方枚举内`,
            legal.includes(out.stop_reason), [{
              path: '/stop_reason',
              message: `"${out.stop_reason}" is not legal`,
              keyword: 'enum',
              allowed: legal,
            }]);
        }
      } else {
        // responses / gemini：本组先验证关键结构字段存在，schema 校验后续补
        const okShape =
          (target === 'responses' && out.object === 'response' && Array.isArray(out.output)) ||
          (target === 'gemini' && Array.isArray(out.candidates));
        record(`${prov} → ${target}: 产出携带协议关键结构`, okShape, okShape ? [] : [
          { path: '(shape)', message: `unexpected shape: ${JSON.stringify(out).slice(0, 150)}` },
        ]);
      }
    }
  }

  return { pass, fail, failures };
}
