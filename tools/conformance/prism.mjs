/**
 * Prism 驱动器 —— Node 侧加载 MoonBit js-target 产物，直接调用真实转换管线。
 *
 * 与 lib.mjs 的关系：
 *   - lib.mjs   = 裁判（官方 schema / 权威枚举）
 *   - prism.mjs = 被测对象（Prism 真实转换层，不是手写样本）
 *
 * 产物构建：`moon build --target js src/cmd/repl`（见 repo 根 scripts/verify.sh 与 CI）。
 * ABI 与 wasm 层一致：String 进 / String 出 / `{"value":...,"diagnostics":[...]}` 信封。
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '..', '..');

/** 产物查找顺序：release → debug */
const ARTIFACTS = [
  '_build/js/release/build/cmd/repl/repl.js',
  '_build/js/debug/build/cmd/repl/repl.js',
];

function findArtifact() {
  for (const rel of ARTIFACTS) {
    const p = path.join(REPO, rel);
    if (fs.existsSync(p)) return p;
  }
  return null;
}

let loaded = null;

/**
 * 加载 Prism 驱动。产物必须在 import 前通过构建生成；
 * 若未找到则抛出带修复指引的错误。
 */
export async function load() {
  if (loaded) return loaded;

  const artifact = findArtifact();
  if (!artifact) {
    throw new Error(
      'Prism js-driver 产物不存在。\n' +
        '  请先构建: moon build --target js src/cmd/repl\n' +
        '  （scripts/verify.sh 与 CI 的 oracle job 会自动执行）',
    );
  }

  // moon 产物在 import 时执行 main，把函数挂到 globalThis.__prism
  globalThis.__prism = {};
  await import('file://' + artifact.replaceAll('\\', '/'));
  const raw = globalThis.__prism;

  const need = ['convert_req', 'convert_resp', 'convert_stream', 'list_providers', 'abi_version'];
  const missing = need.filter((k) => typeof raw[k] !== 'function');
  if (missing.length) {
    throw new Error(`Prism 驱动注册不完整，缺少: ${missing.join(', ')}（产物过期？请重新构建）`);
  }

  loaded = {
    abi: JSON.parse(raw.abi_version()),
    providers: JSON.parse(raw.list_providers()),
    /**
     * 调用并解信封。返回 { ok, value, diagnostics, error }。
     * 信封形态：成功 {"value": X, "diagnostics": [...]}，
     *          失败 {"error": "...", "diagnostics": [...]}
     */
    call(fnName, ...args) {
      const envelope = JSON.parse(raw[fnName](...args));
      if (envelope.error !== undefined) {
        return { ok: false, error: envelope.error, diagnostics: envelope.diagnostics ?? [], value: null };
      }
      return { ok: true, value: envelope.value, diagnostics: envelope.diagnostics ?? [], error: null };
    },

    /** convert_req / convert_resp / convert_stream 的快捷方式 */
    convertReq: (source, json, target) => load().then((p) => p.call('convert_req', source, json, target)),
    convertResp: (source, json, target) => load().then((p) => p.call('convert_resp', source, json, target)),
    convertStream: (source, sse, target) => load().then((p) => p.call('convert_stream', source, sse, target)),
    /** 同步版本（load 完成后使用） */
    callSync: {
      convertReq: (source, json, target) => loaded.call('convert_req', source, json, target),
      convertResp: (source, json, target) => loaded.call('convert_resp', source, json, target),
      convertStream: (source, sse, target) => loaded.call('convert_stream', source, sse, target),
    },
  };
  return loaded;
}

/**
 * 把 SSE 文本拆成帧数组，每帧返回 { event, data }。
 * Prism 的流输出是标准 SSE（event: X\ndata: {...}）。
 */
export function parseSse(sseText) {
  const frames = [];
  for (const block of sseText.split('\n\n')) {
    let event = null;
    const dataLines = [];
    for (const line of block.split('\n')) {
      if (line.startsWith('event: ')) event = line.slice(7).trim();
      else if (line.startsWith('data: ')) dataLines.push(line.slice(6));
      else if (line.startsWith('data:')) dataLines.push(line.slice(5).trim());
    }
    if (event !== null || dataLines.length) {
      frames.push({ event, data: dataLines.join('\n') });
    }
  }
  return frames;
}
