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
  // CR-007 §1：OpenAI legacy function calling（单数 message.function_call，
  // 无 id）。此前完全无解码分支 → 工具调用整体丢失且零诊断。此样本让
  // [5] 组的跨协议矩阵覆盖这条真实存量路径。
  'openai-legacy-fc': {
    response: {
      id: 'chatcmpl-legacy',
      object: 'chat.completion',
      created: 1700000000,
      model: 'gpt-4o',
      choices: [
        {
          index: 0,
          message: {
            role: 'assistant',
            content: null,
            function_call: { name: 'search', arguments: '{"q":"x"}' },
          },
          finish_reason: 'function_call',
        },
      ],
      usage: { prompt_tokens: 3, completion_tokens: 2, total_tokens: 5 },
    },
    // 真相断言：这条路径的价值就是「工具体幸存」，schema 通过还不够
    source: 'openai',
    expectToolUse: true,
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

/**
 * 跑真实管线校验。返回 { pass, fail, failures }。
 * 每家源协议样本：decode → IR，再 encode 到全部 4 家目标，对产出做：
 *   - messages 目标：语义级精确校验（validateAnthropicMessage）
 *   - openai / responses / gemini：官方 schema 整体校验
 *     （2026-10-24 起四家目标全部完整 schema 化；responses 的请求回显槽位
 *      与 gemini 信封形态的处理见 lib.mjs 豁免登记与 docs 本文件头注）
 */
export async function run() {
  const P = await load();
  console.log('\n[5] 真实管线校验（Prism 实际产出 → 官方 schema）');
  console.log(`    driver abi=${P.abi.value?.abi ?? '?'} providers=${P.providers.join(',')}`);

  // 四家目标 → 官方 schema 文件（gemini 用信封级 GenerateContentResponse）
  const TARGET_SCHEMA = {
    openai: 'openai-chat-response.json',
    responses: 'openai-responses-response.json',
    gemini: 'gemini-response.json',
  };

  for (const [prov, s] of Object.entries(SAMPLES)) {
    // 样本可声明真实源协议（样本键名可带变体后缀，如 openai-legacy-fc）
    const src = s.source ?? prov;
    console.log(`\n  源协议 ${prov}`);
    // 1) 官方样本 → IR（decode 必须成功）
    const dec = P.call('to_lux_resp', src, JSON.stringify(s.response));
    if (!dec.ok) {
      record(`${prov}: 官方样本 decode → IR`, false, [{ path: '(driver)', message: dec.error }]);
      continue;
    }
    record(`${prov}: 官方样本 decode → IR（diag=${dec.diagnostics.length}）`, true);

    // 1b) 真相断言：样本声称含工具调用时必须真的解出 tool_use
    //     （CR-007 §1.1 —— schema 全绿但工具体丢失，是此前实际发生的事）
    if (s.expectToolUse) {
      const kinds = dec.value.choices.flatMap((c) =>
        (c.message?.content ?? []).map((b) => b.type));
      record(`${prov}: 解出的 IR 保留工具调用（content 含 tool_use）`,
        kinds.includes('tool_use'), [{
          path: '/choices/0/message/content',
          message: `工具调用丢失，实际 content types = [${kinds.join(', ')}]`,
          keyword: 'expectation',
        }]);
    }

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
        // 整体官方 schema 校验（2026-10-24 升级：此前只查 object 常量，
        // 实测漏掉 choices[].logprobs / message.refusal 两处 required 缺失）
        const r = official(TARGET_SCHEMA.openai, out);
        record(`${prov} → ${target}: 产出符合官方 schema`, r.ok, r.ok ? [] : r.issues);
      } else if (target === 'messages') {
        const issues = validateAnthropicMessage(out);
        record(`${prov} → ${target}: 产出符合官方 Message 形态`, issues.length === 0, issues);
        // 真相断言：源含工具调用 → 目标的 content 必须是非空 tool_use 块。
        // 此前 function_call 源转 messages 产出 {"content":[],"stop_reason":"tool_use"}，
        // 即"声称调了工具却没有任何工具内容"，而 shape 校验全绿（CR-007 §1.1）。
        if (s.expectToolUse) {
          const blocks = out.content ?? [];
          const toolBlocks = blocks.filter((b) => b.type === 'tool_use');
          record(`${prov} → messages: 工具调用块幸存（content 非空且含 tool_use）`,
            toolBlocks.length > 0 && blocks.length > 0, [{
              path: '/content',
              message: `工具调用块丢失：content = ${JSON.stringify(blocks).slice(0, 120)}`,
              keyword: 'expectation',
            }]);
          record(`${prov} → messages: stop_reason 与工具块一致（tool_use）`,
            out.stop_reason === 'tool_use', [{
              path: '/stop_reason',
              message: `有工具块时 stop_reason 应为 tool_use（实际 "${out.stop_reason}"）`,
              keyword: 'expectation',
            }]);
        }
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
      } else if (target === 'responses') {
        // 完整官方 Response schema（豁免登记见 lib.mjs UPSTREAM_BUGS）
        const r = official(TARGET_SCHEMA.responses, out);
        record(`${prov} → ${target}: 产出符合官方 Response schema`, r.ok, r.ok ? [] : r.issues);
        // status 必须在官方封闭枚举内
        const LEGAL_STATUS = ['completed', 'failed', 'in_progress', 'cancelled', 'queued', 'incomplete'];
        record(`${prov} → ${target}: status="${out.status}" 在官方封闭枚举内`,
          LEGAL_STATUS.includes(out.status), LEGAL_STATUS.includes(out.status) ? [] : [{
            path: '/status', message: `"${out.status}" is not a legal response status`,
            keyword: 'enum', allowed: LEGAL_STATUS,
          }]);
      } else {
        // gemini：信封级官方 schema（GenerateContentResponse）
        const r = official(TARGET_SCHEMA.gemini, out);
        record(`${prov} → ${target}: 产出符合官方 GenerateContentResponse schema`, r.ok, r.ok ? [] : r.issues);
        // finishReason 必须在权威枚举内
        const fr = out.candidates?.[0]?.finishReason;
        if (fr !== undefined && fr !== null) {
          const legal = authority()['gemini.finishReason'];
          record(`${prov} → ${target}: finishReason="${fr}" 在官方枚举内`, legal.includes(fr), [{
            path: '/candidates/0/finishReason',
            message: `"${fr}" is not legal gemini.finishReason`,
            keyword: 'enum',
            allowed: legal,
          }]);
        }
      }
    }
  }

  return { pass, fail, failures };
}
