#!/usr/bin/env node
/**
 * Prism 全量校验入口 —— CI/CD 与本地只需跑这一个命令。
 *
 *   node tools/conformance/run-all.mjs
 *
 * 依次执行：
 *   0. 依赖自检（node_modules 是否就位）
 *   1. 生成 schema（从官方 SDK 反射；产物入库，此处确保与当前 SDK 一致）
 *   2. 抽取 golden（从 vendored OpenAPI；确保与官方 spec 一致）
 *   3. 校验器自检（护栏：豁免机制不得放过真错）
 *   4. 权威枚举 + schema 自检 + 跨协议泄漏 + golden 回放
 *
 * 任一步失败即中断并返回非零退出码。
 */
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '..', '..');

let step = 0;
function run(title, argv, opts = {}) {
  step++;
  console.log(`\n[${step}] ${title}`);
  const r = spawnSync(process.execPath, argv, {
    cwd: opts.cwd ?? HERE,
    stdio: 'inherit',
    env: process.env,
  });
  if (r.status !== 0) {
    console.error(`\n✗ 失败于步骤 ${step}: ${title}`);
    process.exit(r.status ?? 1);
  }
}

// ── 0. 依赖自检 ──
console.log('Prism Conformance — 全量校验');
const nm = path.join(HERE, 'node_modules');
const need = ['ajv', 'yaml', 'openai', '@anthropic-ai/sdk', '@google/genai'];
const missing = need.filter((p) => !fs.existsSync(path.join(nm, p)));
if (missing.length) {
  console.error(`\n✗ 缺少依赖: ${missing.join(', ')}`);
  console.error(`  请先运行: cd tools/conformance && npm install`);
  process.exit(1);
}
console.log('  ✓ 依赖就位');

// ── 1..4 ──
run('生成 schema（从官方 SDK）', ['gen-schemas.mjs']);
run('抽取 golden（从 vendored OpenAPI）', ['extract-golden.mjs']);
run('校验器自检（豁免机制护栏）', ['self-check.mjs']);
run('一致性校验（权威枚举 / schema / 跨协议 / golden）', ['validate.mjs']);

console.log('\n' + '='.repeat(60));
console.log('✓ 全部校验通过');
