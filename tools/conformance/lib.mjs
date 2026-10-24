/**
 * Prism 一致性校验证书（Conformance Oracle）—— 核心校验库。
 *
 * 设计原则：**MUST 区分「官方不接受」与「我们不完整」**。
 *   - official()：拿官方 schema 判，只报"这份 JSON 会被真实 API 拒绝"的问题。
 *   - authority()：拿权威枚举判，只报"值不在官方取值集合内"的问题。
 *   - invariant()：跨协议语义不变量，判"同源往返是否 Exact"这类框架级约束。
 *
 * 三者分开的原因：官方 schema 含大量本仓库不建模的可选字段（usage.speed 等），
 * 混在一起会产生噪音，让真实问题被淹没。
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import Ajv from 'ajv';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SCHEMAS = path.join(HERE, 'schemas');

const cache = new Map();
function loadJson(name) {
  if (!cache.has(name)) {
    cache.set(name, JSON.parse(fs.readFileSync(path.join(SCHEMAS, name), 'utf8')));
  }
  return cache.get(name);
}

export function authority() {
  return loadJson('authority.json');
}

/**
 * OpenAPI 3.0 的 `nullable: true` 不是 JSON Schema 关键字，ajv 会直接报错。
 * 转成 type 数组。这是使用 vendored OpenAPI 的必需预处理。
 */
function fixNullable(node) {
  if (Array.isArray(node)) return node.map(fixNullable);
  if (node && typeof node === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(node)) out[k] = fixNullable(v);
    if (out.nullable === true) {
      delete out.nullable;
      if (typeof out.type === 'string') out.type = [out.type, 'null'];
      else if (Array.isArray(out.type) && !out.type.includes('null')) out.type = [...out.type, 'null'];
    } else if ('nullable' in out) {
      delete out.nullable;
    }
    return out;
  }
  return node;
}

const ajv = new Ajv({ strict: false, allErrors: true, validateFormats: false });

const compiled = new Map();

/** 编译一个 SDK 生成的 schema（带 definitions 自引用） */
function compileSdk(schemaFile) {
  const key = 'sdk:' + schemaFile;
  if (!compiled.has(key)) {
    const s = loadJson(schemaFile);
    compiled.set(key, ajv.compile({ ...s, definitions: s.definitions ?? {} }));
  }
  return compiled.get(key);
}

/** 哪些字段属于"本仓库不建模、官方可选"的噪音字段 */
const NOISE_KNOWN = new Set([
  'speed', 'service_tier', 'inference_geo', 'container', 'diagnostics',
  'stop_details', 'server_tool_use', 'cache_creation',
  // 新版官方 SDK 新增、但 vendored spec 里 2025 年的内嵌样本尚未包含的字段。
  // 这些不是 Prism 的问题，是上游 schema 演进快于示例更新。归入噪音，
  // 避免把"样本过时"误报成"转换错误"。
  'access_programs', 'output_text', 'input_tokens_details', 'safety_identifier',
]);

/**
 * 已知的上游 schema 缺陷：官方 SDK 的 TS 类型与真实 wire 不符的地方。
 *
 * 每一条都必须写明依据，且**只豁免具体实例**（路径 + 错误类型），不做通配。
 * 这是为了不让"豁免机制"变成掩盖真实问题的后门。
 */
const UPSTREAM_BUGS = [
  {
    // 官方 SDK 的 Response.user 声明为 `string`（无 null），但真实 API 返回 null，
    // 且 vendored spec 的示例里就是 null。属 SDK 类型遗漏 nullable。
    id: 'responses.user-not-nullable',
    match: (e) => e.instancePath === '/user' && e.keyword === 'type',
    note: '官方 SDK 把 Response.user 声明为 string，真实返回 null',
  },
];

/**
 * 判断一条 ajv 错误是否属于"噪音"：即本仓库未建模的扩展字段缺失。
 * 只过滤 required 类错误，类型/枚举/常量错误一律保留。
 */
function isNoise(err) {
  if (err.keyword !== 'required') return false;
  const prop = err.params?.missingProperty;
  if (!prop) return false;
  return NOISE_KNOWN.has(prop);
}

function isKnownUpstreamBug(err) {
  return UPSTREAM_BUGS.some((b) => b.match(err));
}

/** 官方 SDK 的 Response 有 additionalProperties:false，但样本含此后新增的字段 */
const LATE_ADDED_FIELDS = new Set([
  'access_programs', 'output_text', 'safety_identifier', 'prompt_cache_key',
  'service_tier', 'background', 'max_tool_calls', 'truncation', 'store',
]);

function isLateAdded(err) {
  if (err.keyword !== 'additionalProperties') return false;
  const prop = err.params?.additionalProperty;
  return prop ? LATE_ADDED_FIELDS.has(prop) : false;
}

function realErrors(errors) {
  return (errors ?? []).filter(
    (e) => !isNoise(e) && !isKnownUpstreamBug(e) && !isLateAdded(e),
  );
}

/**
 * 用官方 schema 校验一份 Prism 产出的 JSON。
 * 返回 { ok, issues: [{ path, message, keyword }] }
 */
export function official(schemaFile, payload) {
  const validate = compileSdk(schemaFile);
  const ok = validate(payload);
  if (ok) return { ok: true, issues: [] };
  const errs = realErrors(validate.errors);
  return {
    ok: errs.length === 0,
    issues: errs.map((e) => ({
      path: e.instancePath || '(root)',
      message: e.message,
      keyword: e.keyword,
      missing: e.params?.missingProperty,
      allowed: e.params?.allowedValues,
    })),
  };
}

/**
 * 权威枚举校验：值是否在官方取值集合内。
 * 这是最能抓"我手写了不存在的值 / 漏了官方值"的一类。
 */
export function authorityCheck(kind, value) {
  const a = authority();
  const legal = a[kind];
  if (!legal) {
    return { ok: false, issues: [{ path: kind, message: 'unknown authority kind', keyword: 'authority' }] };
  }
  if (legal.includes(value)) return { ok: true, issues: [] };
  return {
    ok: false,
    issues: [{
      path: kind,
      message: `"${value}" is not a legal ${kind}`,
      keyword: 'authority',
      allowed: legal,
    }],
  };
}

/**
 * 跨协议语义不变量：检查一次转换是否泄漏了源协议的词汇。
 *
 * 这是本仓库最容易错的点（CR-005 的 pause_turn 泄漏到 openai 就是此类）。
 * 返回所有越界值，而不是第一个。
 */
export function crossProtocolCheck(targetKind, values) {
  const a = authority();
  const legal = a[targetKind];
  if (!legal) {
    return { ok: false, issues: [{ path: targetKind, message: 'unknown authority kind', keyword: 'authority' }] };
  }
  const bad = values.filter((v) => !legal.includes(v));
  if (bad.length === 0) return { ok: true, issues: [] };
  return {
    ok: false,
    issues: bad.map((v) => ({
      path: targetKind,
      message: `leaked value "${v}" is not legal for ${targetKind}`,
      keyword: 'cross-protocol',
      allowed: legal,
    })),
  };
}

/** 把 issues 渲染成人读文本 */
export function formatIssues(issues) {
  return issues
    .map((i) => {
      let s = `  ${i.path}: ${i.message}`;
      if (i.missing) s += ` (missing: ${i.missing})`;
      if (Array.isArray(i.allowed) && i.allowed.length <= 12) {
        s += `\n    allowed: ${i.allowed.join(', ')}`;
      }
      return s;
    })
    .join('\n');
}
