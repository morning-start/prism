// TASK-4 integration tests for the Prism TS wrapper (ACC-001 / TC-1..TC-4).
//
// Prereq: the wasm-gc artifact must exist — run `moon build --target wasm-gc`
// from the repo root first. Tests fail loudly when it is missing (fail-fast,
// matching the repo's guard philosophy; CI builds before testing).
//
// Run: npm run build && npm test   (from wrappers/ts)
import { test, before, after } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync, existsSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

import {
  loadPrism,
  PrismClient,
  PrismError,
} from '../dist/index.js'

const here = dirname(fileURLToPath(import.meta.url))
const artifactPath = process.env.PRISM_WASM_PATH
  ?? join(here, '..', '..', '..', '_build', 'wasm-gc', 'debug', 'build', 'cmd', 'main', 'main.wasm')

let client

before(async () => {
  assert.ok(
    existsSync(artifactPath),
    `wasm-gc artifact not found at ${resolve(artifactPath)} — run "moon build --target wasm-gc" from the repo root`,
  )
  client = await loadPrism(readFileSync(artifactPath))
})

// Minimal OpenAI Chat Completions request; no max_tokens → the messages target
// backfills 4096 with a Degraded diagnostic (documented behavior).
const OPENAI_REQ = JSON.stringify({
  model: 'gpt-4o-mini',
  messages: [{ role: 'user', content: 'hello prism wrapper' }],
})
const OPENAI_REQ_EXACT = JSON.stringify({
  model: 'gpt-4o-mini',
  max_tokens: 1024,
  messages: [{ role: 'user', content: 'hello prism wrapper' }],
})

const messagesContentText = result => {
  const parsed = JSON.parse(result.value)
  const first = parsed.messages?.[0]
  const text = first?.content?.[0]?.text
  assert.equal(first?.role, 'user')
  assert.equal(text, 'hello prism wrapper')
  return text
}

// --- Load & ABI anchoring ----------------------------------------------------

test('loadPrism returns a client with abi=1 and known providers', () => {
  assert.equal(client.abiVersion, '1')
  const providers = client.listProviders()
  for (const p of ['responses', 'openai', 'messages', 'gemini']) {
    assert.ok(providers.includes(p), `expected provider ${p} in ${JSON.stringify(providers)}`)
  }
})

test('loadPrism rejects an ABI mismatch (locking contract)', async () => {
  await assert.rejects(
    loadPrism(readFileSync(artifactPath), { expectedAbi: '999' }),
    (err) => err instanceof PrismError && err.code === 'ABI_MISMATCH',
  )
})

test('loadPrism rejects corrupt bytes with LOAD_FAILED', async () => {
  const garbage = Buffer.from('this is not a wasm module')
  await assert.rejects(
    loadPrism(garbage),
    (err) => err instanceof PrismError && err.code === 'LOAD_FAILED',
  )
})

// --- TC-1: request conversion ------------------------------------------------

test('TC-1: convertRequest openai→messages is semantically equivalent to the raw ABI', async () => {
  const result = client.convertRequest('openai', OPENAI_REQ_EXACT, 'messages')
  messagesContentText(result)
  assert.equal(JSON.parse(result.value).max_tokens, 1024)
  assert.deepEqual(result.diagnostics, [])
  // wrapper adds nothing: a second client on the same bytes must give identical output
  const client2 = await loadPrism(readFileSync(artifactPath))
  const again = client2.convertRequest('openai', OPENAI_REQ_EXACT, 'messages')
  assert.equal(again.value, result.value)
})

// --- TC-3: diagnostics surfacing ----------------------------------------------

test('TC-3: Degraded diagnostics surface to the caller (never swallowed)', () => {
  const result = client.convertRequest('openai', OPENAI_REQ, 'messages')
  messagesContentText(result)
  assert.equal(JSON.parse(result.value).max_tokens, 4096)
  assert.ok(result.diagnostics.length >= 1, 'expected at least one diagnostic')
  const degraded = result.diagnostics.find(d => d.status === 'degraded')
  assert.ok(degraded, 'expected a Degraded diagnostic for the backfilled max_tokens')
  assert.ok(typeof degraded.field === 'string' && degraded.field.length > 0)
})

// --- TC-2: streaming equivalence ----------------------------------------------

const STREAM_FRAMES = [
  JSON.stringify({
    id: 'w1', object: 'chat.completion.chunk', created: 1, model: 'gpt-4o-mini',
    choices: [{ index: 0, delta: { role: 'assistant', content: 'Hel' }, finish_reason: null }],
  }),
  JSON.stringify({
    id: 'w1', object: 'chat.completion.chunk', created: 1, model: 'gpt-4o-mini',
    choices: [{ index: 0, delta: { content: 'lo' }, finish_reason: null }],
  }),
  JSON.stringify({
    id: 'w1', object: 'chat.completion.chunk', created: 1, model: 'gpt-4o-mini',
    choices: [{ index: 0, delta: {}, finish_reason: 'stop' }],
  }),
].map(j => `data: ${j}\n\n`) + 'data: [DONE]\n\n'

test('TC-2: incremental session output === whole-batch conversion', () => {
  const batch = client.convertStream('openai', STREAM_FRAMES, 'messages')
  assert.ok(batch.value.includes('message_start'))
  assert.ok(batch.value.includes('message_stop'))

  const session = client.createStream('openai', 'messages')
  let acc = ''
  try {
    for (const frame of STREAM_FRAMES.split('\n\n').filter(s => s.length > 0).map(s => `${s}\n\n`)) {
      for (const out of session.feed(frame)) acc += out
    }
    for (const out of session.finish()) acc += out
  } finally {
    session.free()
  }
  assert.equal(acc, batch.value, 'session feed+finish concatenation must equal batch conversion')
})

test('TC-2b: split tool-call arguments across chunks reassemble', () => {
  const mk = (delta, fin) =>
    `data: ${JSON.stringify({
      id: 't1', object: 'chat.completion.chunk', created: 1, model: 'gpt-4o-mini',
      choices: [{ index: 0, delta, finish_reason: fin }],
    })}\n\n`
  const frames = [
    mk({ role: 'assistant', tool_calls: [{ index: 0, id: 'call_1', type: 'function', function: { name: 'get_weather', arguments: '' } }] }, null),
    mk({ tool_calls: [{ index: 0, function: { arguments: '{"loc' } }] }, null),
    mk({ tool_calls: [{ index: 0, function: { arguments: 'ation":"Tokyo"}' } }] }, null),
    mk({}, 'tool_calls'),
    'data: [DONE]\n\n',
  ]
  const session = client.createStream('openai', 'messages')
  let acc = ''
  try {
    for (const f of frames) for (const out of session.feed(f)) acc += out
    for (const out of session.finish()) acc += out
  } finally {
    session.free()
  }
  // Anthropic streaming: tool args arrive as input_json_delta partial_json chunks.
  const deltas = [...acc.matchAll(/\{"type":"content_block_delta","index":0,"delta":\{"type":"input_json_delta","partial_json":"((?:[^"\\]|\\.)*)"\}\}/g)]
  const joined = deltas.map(m => JSON.parse(`"${m[1]}"`)).join('')
  assert.ok(acc.includes('"type":"tool_use"') && acc.includes('"name":"get_weather"'), 'tool_use block must open')
  assert.equal(joined, '{"location":"Tokyo"}', 'split argument chunks must reassemble')
})

// --- TC-4: termination edge cases ----------------------------------------------

test('TC-4: session abandoned without finish() does not hang; free() is idempotent', () => {
  const session = client.createStream('openai', 'messages')
  const frames = session.feed(STREAM_FRAMES)
  assert.ok(frames.length >= 1)
  session.free()
  session.free() // second free is a no-op
})

test('TC-4b: feed() after finish() throws SESSION_STATE (documented behavior)', () => {
  const session = client.createStream('openai', 'messages')
  try {
    session.feed(STREAM_FRAMES)
    session.finish()
    assert.throws(
      () => session.feed('data: {}\n\n'),
      (err) => err instanceof PrismError && err.code === 'SESSION_STATE',
    )
  } finally {
    session.free()
  }
})

test('TC-4c: finished() self-check flips false→true across finish', () => {
  const session = client.createStream('openai', 'messages')
  try {
    assert.equal(session.finished(), false)
    session.finish()
    assert.equal(session.finished(), true)
  } finally {
    session.free()
  }
})

// --- Error paths ----------------------------------------------------------------

test('unknown provider raises PrismError CONVERSION_ERROR', () => {
  assert.throws(
    () => client.convertRequest('nonexistent', OPENAI_REQ, 'messages'),
    (err) =>
      err instanceof PrismError
      && err.code === 'CONVERSION_ERROR'
      && /unknown provider/.test(err.message),
  )
})

test('free() then feed() raises SESSION_STATE', () => {
  const session = client.createStream('openai', 'messages')
  session.free()
  assert.throws(
    () => session.feed('data: {}\n\n'),
    (err) => err instanceof PrismError && err.code === 'SESSION_STATE',
  )
})

after(() => {
  // PrismClient holds no host resources beyond the instance; nothing to release.
})
