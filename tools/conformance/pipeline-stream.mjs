/**
 * [6] 真实流式管线校验 —— convert_stream 的 oracle 级验证。
 *
 * [5] 组校验非流式响应管线；这一组校验**流式**管线：
 *
 *   官方形态 SSE 帧序列 → Prism convert_stream（js driver，零编组）
 *     → 目标协议 SSE 帧序列 → 逐帧官方 schema/形态 + 帧序契约
 *
 * 帧序契约（CR-002/CR-003 建立的保证，在 oracle 层复核）：
 *   - openai   ：恰一个 finish_reason 帧 + [DONE] 终止符
 *   - messages  ：message_start 开头、恰一个 message_stop 结尾、
 *                 content block 的 start/delta/stop 索引生命周期
 *   - responses ：response.created 开头、恰一个终止事件（completed/incomplete/failed）且在最后
 *   - gemini    ：恰一个 finishReason 且在最后
 *
 * 流式终止修复（CR-006 批次 1）的四个样本（response.incomplete / response.failed /
 * 官方扁平 error 帧 / gemini promptFeedback.blockReason）作为独立源样本纳入 ——
 * oracle 与 MoonBit 回归测试双重锁定。
 */
import { load, parseSse } from './prism.mjs';
import { authority, formatIssues } from './lib.mjs';

// ── 官方形态的源 SSE 样本 ──────────────────────────────────────────────
// 字段集来自各协议官方文档/SDK 类型；终止类样本即 CR-006 批次 1 修复的输入。

function openaiChunk(delta, finishReason = null, usage = null) {
  const c = { index: 0, delta, finish_reason: finishReason };
  const body = {
    id: 'chatcmpl-x',
    object: 'chat.completion.chunk',
    created: 1700000000,
    model: 'gpt-4o',
    choices: [c],
  };
  if (usage) body.usage = usage;
  return `data: ${JSON.stringify(body)}\n\n`;
}

function anthropicFrame(type, extra = {}) {
  return `event: ${type}\ndata: ${JSON.stringify({ type, ...extra })}\n\n`;
}

function responsesFrame(type, extra = {}) {
  return `event: ${type}\ndata: ${JSON.stringify({ type, ...extra })}\n\n`;
}

const RESPONSE_MSG_ITEM = {
  type: 'message',
  id: 'msg_x',
  status: 'completed',
  role: 'assistant',
  content: [{ type: 'output_text', text: 'Hi', annotations: [] }],
};
const RESPONSE_USAGE = {
  input_tokens: 3,
  input_tokens_details: { cached_tokens: 0 },
  output_tokens: 2,
  output_tokens_details: { reasoning_tokens: 0 },
  total_tokens: 5,
};

const STREAM_SAMPLES = {
  openai: {
    sse:
      openaiChunk({ role: 'assistant', content: 'Hi' }) +
      openaiChunk({}) +
      openaiChunk({}, 'stop', { prompt_tokens: 3, completion_tokens: 2, total_tokens: 5 }) +
      'data: [DONE]\n\n',
  },
  messages: {
    sse:
      anthropicFrame('message_start', {
        message: {
          id: 'msg_x', type: 'message', role: 'assistant', model: 'claude-sonnet-4',
          content: [], stop_reason: null, stop_sequence: null,
          usage: { input_tokens: 3, output_tokens: 1 },
        },
      }) +
      anthropicFrame('content_block_start', { index: 0, content_block: { type: 'text', text: '' } }) +
      anthropicFrame('content_block_delta', { index: 0, delta: { type: 'text_delta', text: 'Hi' } }) +
      anthropicFrame('content_block_stop', { index: 0 }) +
      anthropicFrame('message_delta', {
        delta: { stop_reason: 'end_turn', stop_sequence: null },
        usage: { output_tokens: 2 },
      }) +
      anthropicFrame('message_stop'),
  },
  responses: {
    sse:
      responsesFrame('response.created', {
        response: {
          id: 'resp_x', object: 'response', created_at: 1700000000,
          status: 'in_progress', model: 'gpt-4o', output: [],
        },
      }) +
      responsesFrame('response.output_item.added', {
        output_index: 0,
        item: { type: 'message', id: 'msg_x', status: 'in_progress', role: 'assistant', content: [] },
      }) +
      // 官方流序：output_item.added → content_part.added → *.delta → *.done
      // → output_item.done → 终止事件（vendored spec 内嵌样本的逐帧顺序）
      responsesFrame('response.content_part.added', {
        item_id: 'msg_x', output_index: 0, content_index: 0,
        part: { type: 'output_text', text: '', annotations: [] },
      }) +
      responsesFrame('response.output_text.delta', {
        item_id: 'msg_x', output_index: 0, content_index: 0, delta: 'Hi',
      }) +
      responsesFrame('response.output_text.done', {
        item_id: 'msg_x', output_index: 0, content_index: 0, text: 'Hi',
      }) +
      responsesFrame('response.output_item.done', { output_index: 0, item: RESPONSE_MSG_ITEM }) +
      responsesFrame('response.completed', {
        response: {
          id: 'resp_x', object: 'response', created_at: 1700000000,
          status: 'completed', model: 'gpt-4o', output: [RESPONSE_MSG_ITEM], usage: RESPONSE_USAGE,
        },
      }),
  },
  gemini: {
    sse:
      'data: ' + JSON.stringify({
        candidates: [{ content: { parts: [{ text: 'Hi' }], role: 'model' }, index: 0 }],
        usageMetadata: { promptTokenCount: 3, candidatesTokenCount: 2, totalTokenCount: 5 },
        modelVersion: 'gemini-2.0-flash', responseId: 'r1',
      }) + '\n\n' +
      'data: ' + JSON.stringify({
        candidates: [{ content: { parts: [], role: 'model' }, finishReason: 'STOP', index: 0 }],
        usageMetadata: { promptTokenCount: 3, candidatesTokenCount: 2, totalTokenCount: 5 },
        modelVersion: 'gemini-2.0-flash', responseId: 'r1',
      }) + '\n\n',
  },
};

// CR-006 批次 1 修复的终止/错误输入：oracle 与 MoonBit 回归双锁定
const TERMINATION_SAMPLES = {
  'responses/incomplete(content_filter)': {
    source: 'responses',
    sse:
      responsesFrame('response.created', {
        response: {
          id: 'resp_x', object: 'response', created_at: 1700000000,
          status: 'in_progress', model: 'gpt-4o', output: [],
        },
      }) +
      responsesFrame('response.output_item.added', {
        output_index: 0,
        item: { type: 'message', id: 'msg_x', status: 'in_progress', role: 'assistant', content: [] },
      }) +
      responsesFrame('response.content_part.added', {
        item_id: 'msg_x', output_index: 0, content_index: 0,
        part: { type: 'output_text', text: '', annotations: [] },
      }) +
      responsesFrame('response.output_text.delta', {
        item_id: 'msg_x', output_index: 0, content_index: 0, delta: 'Hi',
      }) +
      responsesFrame('response.output_text.done', {
        item_id: 'msg_x', output_index: 0, content_index: 0, text: 'Hi',
      }) +
      responsesFrame('response.output_item.done', { output_index: 0, item: RESPONSE_MSG_ITEM }) +
      responsesFrame('response.incomplete', {
        response: {
          id: 'resp_x', object: 'response', created_at: 1700000000,
          status: 'incomplete', model: 'gpt-4o', output: [RESPONSE_MSG_ITEM],
          incomplete_details: { reason: 'content_filter' },
          usage: RESPONSE_USAGE,
        },
      }),
    // 下游 messages 目标必须看到 refusal + message_stop，而不是空流
    expect: { messages: { stop_reason: 'refusal' } },
  },
  'responses/failed': {
    source: 'responses',
    sse:
      responsesFrame('response.created', {
        response: {
          id: 'resp_x', object: 'response', created_at: 1700000000,
          status: 'in_progress', model: 'gpt-4o', output: [],
        },
      }) +
      responsesFrame('response.failed', {
        response: {
          id: 'resp_x', object: 'response', created_at: 1700000000,
          status: 'failed', model: 'gpt-4o', output: [],
          error: { code: 'server_error', message: 'boom' },
        },
      }),
    expect: { messages: { error_seen: true } },
  },
  'responses/error-frame(flat)': {
    source: 'responses',
    sse:
      responsesFrame('response.created', {
        response: {
          id: 'resp_x', object: 'response', created_at: 1700000000,
          status: 'in_progress', model: 'gpt-4o', output: [],
        },
      }) +
      responsesFrame('error', {
        code: 'server_error', message: 'boom', param: null, sequence_number: 3,
      }),
    expect: { messages: { error_seen: true } },
  },
  'gemini/promptFeedback-blockReason': {
    source: 'gemini',
    sse:
      'data: ' + JSON.stringify({
        promptFeedback: { blockReason: 'PROHIBITED_CONTENT' },
        usageMetadata: { promptTokenCount: 3, totalTokenCount: 3 },
        modelVersion: 'gemini-2.0-flash', responseId: 'r1',
      }) + '\n\n',
    expect: { messages: { stop_reason: 'refusal' } },
  },
};

// ── 帧序契约（目标协议的官方流事件合法性）────────────────────────────────

const MESSAGES_EVENT_TYPES = new Set([
  'message_start', 'content_block_start', 'content_block_delta',
  'content_block_stop', 'message_delta', 'message_stop', 'ping', 'error',
]);

function issuesFor(target, frames) {
  const issues = [];
  const A = authority();
  const jsonFrames = [];

  // 每帧都是合法 JSON（[DONE] 等非 JSON 终止符除外）
  for (let i = 0; i < frames.length; i++) {
    const f = frames[i];
    if (f.data === '[DONE]') { jsonFrames.push(null); continue; }
    try {
      jsonFrames.push(JSON.parse(f.data));
    } catch {
      issues.push({ path: `/frame/${i}`, message: `产出帧不是合法 JSON: ${f.data.slice(0, 80)}`, keyword: 'json' });
      jsonFrames.push(null);
    }
  }

  if (target === 'openai') {
    for (let i = 0; i < jsonFrames.length; i++) {
      const o = jsonFrames[i];
      if (!o) continue;
      if (o.object !== 'chat.completion.chunk') {
        issues.push({ path: `/frame/${i}/object`, message: `must be "chat.completion.chunk" (got "${o.object}")`, keyword: 'const' });
      }
    }
    const doneIdx = frames.findIndex((f) => f.data === '[DONE]');
    if (doneIdx === -1) {
      issues.push({ path: '(terminator)', message: '缺少 data: [DONE] 终止符', keyword: 'required' });
    } else if (doneIdx !== frames.length - 1) {
      issues.push({ path: '(terminator)', message: `[DONE] 不是最后一帧（位置 ${doneIdx}/${frames.length - 1}）`, keyword: 'order' });
    }
    const fin = [];
    for (let i = 0; i < jsonFrames.length; i++) {
      const fr = jsonFrames[i]?.choices?.[0]?.finish_reason;
      if (fr !== undefined && fr !== null) fin.push([i, fr]);
    }
    if (fin.length !== 1) {
      issues.push({ path: '(finish_reason)', message: `finish_reason 帧数量必须为 1（got ${fin.length}）`, keyword: 'unique' });
    } else {
      const [i, fr] = fin[0];
      if (!A['openai.finish_reason'].includes(fr)) {
        issues.push({ path: `/frame/${i}/choices/0/finish_reason`, message: `"${fr}" is not legal openai.finish_reason`, keyword: 'enum', allowed: A['openai.finish_reason'] });
      }
      if (doneIdx !== -1 && i > doneIdx) {
        issues.push({ path: '(order)', message: 'finish_reason 帧出现在 [DONE] 之后', keyword: 'order' });
      }
    }
  }

  if (target === 'messages') {
    const types = jsonFrames.map((o, i) => {
      if (!o) return null;
      if (!MESSAGES_EVENT_TYPES.has(o.type)) {
        issues.push({ path: `/frame/${i}/type`, message: `"${o.type}" 不是官方 messages 流事件类型`, keyword: 'enum', allowed: [...MESSAGES_EVENT_TYPES] });
        return null;
      }
      return o.type;
    });
    if (types[0] !== 'message_start') {
      issues.push({ path: '(order)', message: `首帧必须是 message_start（got ${types[0]}）`, keyword: 'order' });
    }
    const stops = types.filter((t) => t === 'message_stop');
    if (stops.length !== 1) {
      issues.push({ path: '(terminator)', message: `message_stop 数量必须为 1（got ${stops.length}）`, keyword: 'unique' });
    } else if (types[types.length - 1] !== 'message_stop') {
      issues.push({ path: '(order)', message: 'message_stop 不是最后一帧', keyword: 'order' });
    }
    // content block 索引生命周期：delta 前必须有 start，stop 后不得再有 delta
    const open = new Set();
    const closed = new Set();
    for (let i = 0; i < jsonFrames.length; i++) {
      const o = jsonFrames[i];
      if (!o) continue;
      if (o.type === 'content_block_start') open.add(o.index);
      else if (o.type === 'content_block_delta') {
        if (closed.has(o.index)) issues.push({ path: `/frame/${i}`, message: `content_block ${o.index} 已 stop 后仍有 delta`, keyword: 'order' });
        else if (!open.has(o.index)) issues.push({ path: `/frame/${i}`, message: `content_block_delta 的 index ${o.index} 未经 start`, keyword: 'order' });
      } else if (o.type === 'content_block_stop') {
        if (!open.has(o.index)) issues.push({ path: `/frame/${i}`, message: `content_block_stop 的 index ${o.index} 未经 start`, keyword: 'order' });
        open.delete(o.index);
        closed.add(o.index);
      } else if (o.type === 'message_delta') {
        const sr = o.delta?.stop_reason;
        if (sr !== undefined && sr !== null && !A['messages.stop_reason'].includes(sr)) {
          issues.push({ path: `/frame/${i}/delta/stop_reason`, message: `"${sr}" is not legal messages.stop_reason`, keyword: 'enum', allowed: A['messages.stop_reason'] });
        }
      }
    }
    for (const idx of open) {
      issues.push({ path: '(blocks)', message: `content_block ${idx} 未闭合（缺 content_block_stop）`, keyword: 'required' });
    }
  }

  if (target === 'responses') {
    for (let i = 0; i < jsonFrames.length; i++) {
      const t = jsonFrames[i]?.type;
      if (t !== undefined && typeof t === 'string' && !t.startsWith('response.') && t !== 'error') {
        issues.push({ path: `/frame/${i}/type`, message: `"${t}" 不是官方 responses 流事件类型`, keyword: 'enum' });
      }
    }
    const TERMINALS = ['response.completed', 'response.incomplete', 'response.failed'];
    const terms = [];
    for (let i = 0; i < jsonFrames.length; i++) {
      if (TERMINALS.includes(jsonFrames[i]?.type)) terms.push(i);
    }
    if (terms.length !== 1) {
      issues.push({ path: '(terminator)', message: `responses 终止事件数量必须为 1（got ${terms.length}）`, keyword: 'unique' });
    } else if (terms[0] !== jsonFrames.length - 1) {
      issues.push({ path: '(order)', message: '终止事件不是最后一帧', keyword: 'order' });
    }
    if (jsonFrames[0]?.type !== 'response.created') {
      issues.push({ path: '(order)', message: `首帧必须是 response.created（got ${jsonFrames[0]?.type}）`, keyword: 'order' });
    }
  }

  if (target === 'gemini') {
    const fin = [];
    for (let i = 0; i < jsonFrames.length; i++) {
      const fr = jsonFrames[i]?.candidates?.[0]?.finishReason;
      if (fr !== undefined && fr !== null) fin.push([i, fr]);
    }
    if (fin.length > 1) {
      issues.push({ path: '(terminator)', message: `finishReason 帧数量必须 ≤ 1（got ${fin.length}）`, keyword: 'unique' });
    } else if (fin.length === 1) {
      const [i, fr] = fin[0];
      if (!A['gemini.finishReason'].includes(fr)) {
        issues.push({ path: `/frame/${i}/candidates/0/finishReason`, message: `"${fr}" is not legal gemini.finishReason`, keyword: 'enum', allowed: A['gemini.finishReason'] });
      }
      if (i !== jsonFrames.length - 1) {
        issues.push({ path: '(order)', message: '带 finishReason 的帧不是最后一帧', keyword: 'order' });
      }
    }
  }

  return issues;
}

// ── 主流程 ────────────────────────────────────────────────────────────

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

export async function run() {
  const P = await load();
  console.log('\n[6] 真实流式管线校验（convert_stream：官方 SSE → Prism → 目标 SSE → 帧序契约）');
  console.log(`    driver abi=${P.abi.value?.abi ?? '?'} providers=${P.providers.join(',')}`);

  const targets = ['openai', 'messages', 'responses', 'gemini'];

  for (const [name, sample] of Object.entries(STREAM_SAMPLES)) {
    console.log(`\n  源协议 ${name}`);
    for (const target of targets) {
      const r = P.call('convert_stream', name, sample.sse, target);
      if (!r.ok) {
        record(`${name} → ${target}: 流式转换`, false, [{ path: '(driver)', message: r.error }]);
        continue;
      }
      const frames = parseSse(r.value);
      if (frames.length === 0) {
        record(`${name} → ${target}: 产出非空帧序列`, false, [{ path: '(frames)', message: '产出 0 帧' }]);
        continue;
      }
      record(`${name} → ${target}: 流式转换（${frames.length} 帧, diag=${r.diagnostics.length}）`, true);

      // 逐帧契约：JSON 合法 + 形态 + 帧序
      const issues = issuesFor(target, frames);
      record(`${name} → ${target}: 产出符合 ${target} 官方流形态与帧序契约`, issues.length === 0, issues);
    }
  }

  // CR-006 批次 1：终止/错误样本的双重锁定
  console.log('\n  终止/错误样本（CR-006 批次 1）');
  for (const [name, sample] of Object.entries(TERMINATION_SAMPLES)) {
    for (const [target, want] of Object.entries(sample.expect)) {
      const r = P.call('convert_stream', sample.source, sample.sse, target);
      if (!r.ok) {
        record(`${name} → ${target}: 终止流不再为空`, false, [{ path: '(driver)', message: r.error }]);
        continue;
      }
      const frames = parseSse(r.value).map((f) => { try { return JSON.parse(f.data); } catch { return null; } });
      const issues = issuesFor(target, parseSse(r.value));

      if (want.stop_reason !== undefined) {
        const sr = frames.find((o) => o?.type === 'message_delta')?.delta?.stop_reason;
        if (sr !== want.stop_reason) {
          issues.push({ path: '(expectation)', message: `期望 message_delta.stop_reason="${want.stop_reason}"，实际 ${JSON.stringify(sr)}`, keyword: 'custom' });
        }
      }
      if (want.error_seen) {
        const hasError = frames.some((o) => o?.type === 'error');
        if (!hasError) {
          issues.push({ path: '(expectation)', message: '期望产出 error 事件（流不得对失败静默）', keyword: 'custom' });
        }
      }
      record(`${name} → ${target}: 终止语义正确且不为空流`, issues.length === 0, issues);
    }
  }

  return { pass, fail, failures };
}
