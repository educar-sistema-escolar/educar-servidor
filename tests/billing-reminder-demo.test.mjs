import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import ts from '../../educar-mobile/node_modules/typescript/lib/typescript.js';

function setup({ authenticated = true, allowed = true, status = 'sent', mode = 'demo' } = {}) {
  let handler, calls = 0;
  const caller = { auth: { getUser: async () => ({ data: { user: authenticated ? { id: 'admin' } : null }, error: null }) }, rpc: async () => allowed ? { data: 'run-1', error: null } : { error: { code: '42501' } } };
  const admin = { from: () => ({ select: () => ({ eq: () => ({ single: async () => ({ data: { id: 'run-1', status, last_error: status === 'failed' ? 'provider_http_400' : null }, error: null }) }) }) }) };
  const source = ts.transpileModule(fs.readFileSync('supabase/functions/billing-reminder-demo/index.ts','utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
  vm.runInNewContext(source, { exports: {}, require: () => ({ createClient: (_url,_key,options) => options ? caller : admin }), Deno: { env: { get: key => key === 'BILLING_DELIVERY_MODE' ? mode : 'fixture' }, serve: fn => { handler = fn; } }, Response, AbortSignal, fetch: async () => { calls++; return new Response('{}'); } });
  return { call: (body, auth = 'Bearer test') => handler(new Request('https://fixture.test', { method:'POST', headers: { Authorization: auth, 'Content-Type':'application/json' }, body: JSON.stringify(body) })), calls: () => calls };
}

test('requires a valid session and administrator authorization', async () => {
  const unauthenticated = setup({ authenticated: false });
  assert.equal((await unauthenticated.call({ kind:'debt' })).status, 401);
  const family = setup({ allowed: false });
  assert.equal((await family.call({ kind:'debt' })).status, 403);
  assert.equal(family.calls(), 0);
});
test('accepts only the two fixed demo actions and refuses live mode', async () => {
  for (const input of [{kind:'debt',recipient:'other@example.test'},{kind:'other'}]) assert.equal((await setup().call(input)).status, 400);
  assert.equal((await setup({mode:'live'}).call({kind:'debt'})).status, 503);
});
test('returns the actual failed result without declaring success', async () => {
  const runtime = setup({status:'failed'});
  const response = await runtime.call({kind:'month_end'});
  const body = await response.json();
  assert.equal(runtime.calls(), 1);
  assert.equal(body.status, 'failed');
  assert.equal(body.last_error, 'provider_http_400');
});
