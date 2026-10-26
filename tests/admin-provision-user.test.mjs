import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import ts from '../../frontend/node_modules/typescript/lib/typescript.js';

function worker({ role = 'superadmin', active = true, validUser = true } = {}) {
  let handler, invitations = 0;
  const client = {
    auth: { getUser: async () => ({ data: { user: validUser ? { id: 'caller' } : null }, error: null }),
      admin: { inviteUserByEmail: async () => { invitations++; throw new Error('Unexpected invitation'); } } },
    from: () => ({ select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: { role, is_active: active }, error: null }) }) }) }),
  };
  const source = ts.transpileModule(fs.readFileSync('supabase/functions/admin-provision-user/index.ts', 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
  }).outputText;
  vm.runInNewContext(source, { exports: {}, require: () => ({ createClient: () => client }),
    Deno: { env: { get: () => 'server-fixture' }, serve: fn => { handler = fn; } }, Response, Set });
  return { call: (method, body, authorization) => handler(new Request('https://fixture.test', {
    method, headers: { ...(authorization ? { Authorization: authorization } : {}), 'Content-Type': 'application/json' },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  })), invitations: () => invitations };
}

test('provisioning preflight advertises POST and requires no session', async () => {
  const r = await worker().call('OPTIONS');
  assert.equal(r.status, 200);
  assert.match(r.headers.get('Access-Control-Allow-Methods'), /POST/);
});
test('provisioning refuses missing or invalid sessions before privileged writes', async () => {
  assert.equal((await worker().call('POST', {})).status, 401);
  const runtime = worker({ validUser: false });
  assert.equal((await runtime.call('POST', {}, 'Bearer invalid')).status, 401);
  assert.equal(runtime.invitations(), 0);
});
test('provisioning refuses non-admin and inactive callers', async () => {
  for (const config of [{ role: 'parent' }, { role: 'teacher' }, { active: false }]) {
    const runtime = worker(config);
    assert.equal((await runtime.call('POST', {}, 'Bearer session')).status, 403);
    assert.equal(runtime.invitations(), 0);
  }
});
test('provisioning rejects arbitrary passwords, invalid roles and incomplete names', async () => {
  for (const body of [
    { email: 'family@example.test', full_name: 'Demo Family', role: 'parent', password: 'forbidden' },
    { email: 'family@example.test', full_name: 'Demo Family', role: 'admin' },
    { email: 'family@example.test', full_name: 'Demo', role: 'parent' },
  ]) {
    const runtime = worker();
    assert.equal((await runtime.call('POST', body, 'Bearer session')).status, 400);
    assert.equal(runtime.invitations(), 0);
  }
});
