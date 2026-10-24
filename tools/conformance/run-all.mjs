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
 *   5. 构建 js driver（MoonBit → js，让 Node 直接驱动真实转换管线）
 *   6. 真实管线校验：官方样本 → Prism → 产出 → 官方 schema
 *   7. 真实流式管线校验：官方 SSE → convert_stream → 帧序契约
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
  // 特殊步骤：构建 js driver（MoonBit 侧，不是 node 脚本）
  if (argv[0] === '--build-driver') {
    const r = spawnSync('moon', ['build', '--target', 'js', 'src/cmd/repl'], {
      cwd: REPO, stdio: 'inherit', env: process.env, shell: process.platform === 'win32',
    });
    if (r.status !== 0) {
      console.error(`\n✗ 失败于步骤 ${step}: ${title}`);
      process.exit(r.status ?? 1);
    }
    return;
  }
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

// ── 1..5 ──
run('生成 schema（从官方 SDK）', ['gen-schemas.mjs']);
run('抽取 golden（从 vendored OpenAPI）', ['extract-golden.mjs']);
run('校验器自检（豁免机制护栏）', ['self-check.mjs']);
run('一致性校验（权威枚举 / schema / 跨协议 / golden）', ['validate.mjs']);

// [5] 真实管线：构建 js-driver 产物并用 Node 驱动真实转换
run('构建 js driver（真实管线产物）', ['--build-driver']);

// 管线校验需要独立的 node 进程（pipeline.mjs 依赖 prism.mjs 的模块态）
{
  step++;
  console.log(`\n[${step}] 真实管线校验（Prism 实际产出 → 官方 schema）`);
  const r = spawnSync(
    process.execPath,
    ['--input-type=module', '-e', `
      import { run } from './pipeline.mjs';
      const s = await run();
      console.log('总计: ' + s.pass + ' pass / ' + s.fail + ' fail');
      process.exit(s.fail ? 1 : 0);
    `],
    { cwd: HERE, stdio: 'inherit', env: process.env },
  );
  if (r.status !== 0) {
    console.error(`\n✗ 失败于步骤 ${step}: 真实管线校验`);
    process.exit(r.status ?? 1);
  }
}

// [6] 真实流式管线：convert_stream 的逐帧契约校验
{
  step++;
  console.log(`\n[${step}] 真实流式管线校验（convert_stream → 帧序契约）`);
  const r = spawnSync(
    process.execPath,
    ['--input-type=module', '-e', `
      import { run } from './pipeline-stream.mjs';
      const s = await run();
      console.log('总计: ' + s.pass + ' pass / ' + s.fail + ' fail');
      process.exit(s.fail ? 1 : 0);
    `],
    { cwd: HERE, stdio: 'inherit', env: process.env },
  );
  if (r.status !== 0) {
    console.error(`\n✗ 失败于步骤 ${step}: 真实流式管线校验`);
    process.exit(r.status ?? 1);
  }
}

console.log('\n' + '='.repeat(60));
console.log('✓ 全部校验通过');
