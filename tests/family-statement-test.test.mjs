import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import ts from '../../educar-mobile/node_modules/typescript/lib/typescript.js';

function setup({ email = 'test@example.com', role = 'parent', student = true } = {}) {
  let handler, sends = 0;
  const values = { SUPABASE_URL: 'https://example.com', SUPABASE_ANON_KEY: 'public', BILLING_TEST_ACCOUNT_EMAIL: 'test@example.com', BILLING_DEMO_RECIPIENT: 'test@example.com', BILLING_DEMO_GUARDIAN_ID: 'user', BILLING_DELIVERY_MODE: 'demo', BILLING_SEND_ENABLED: 'true', BILLING_FROM_EMAIL: 'sender@example.com', RESEND_API_KEY: 'test' };
  const rows = { profiles: { role, is_active: true, account_status: 'active' }, students: student ? { id: '11111111-1111-1111-1111-111111111111', people: { first_name: 'Demo', last_name: 'Alumno' } } : null, invoices: [{ period: '2026-01-01', due_date: '2026-01-10', invoice_items: [{ label: 'Cuota', amount_cents: 1000, paid_cents: 200 }] }] };
  const client = { auth: { getUser: async () => ({ data: { user: { id: email === 'test@example.com' ? 'user' : 'other', email } }, error: null }) }, from: (name) => { const query = { select: () => query, eq: () => query, order: () => query, limit: async () => ({ data: rows[name], error: null }), maybeSingle: async () => ({ data: rows[name], error: null }) }; return query; } };
  const pdf = { embedFont: async () => ({}), addPage: () => ({ drawText() {} }), saveAsBase64: async () => 'cGRm' };
  const code = ts.transpileModule(fs.readFileSync('supabase/functions/family-statement-test/index.ts', 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
  vm.runInNewContext(code, { exports: {}, require: (name) => name.includes('pdf-lib') ? { PDFDocument: { create: async () => pdf }, StandardFonts: { Helvetica: 'Helvetica' } } : { createClient: () => client }, Deno: { env: { get: (name) => values[name] }, serve: fn => { handler = fn; } }, Response, AbortSignal, fetch: async (_url, options) => { sends++; assert.deepEqual(JSON.parse(options.body).to, ['test@example.com']); return { ok: true }; } });
  return { call: (body, auth = 'Bearer valid') => handler(new Request('https://example.com', { method: 'POST', headers: { Authorization: auth }, body: JSON.stringify(body) })), sent: () => sends };
}
const valid = { childId: '11111111-1111-1111-1111-111111111111' };
test('sends a PDF only to configured test account', async () => { const x = setup(); assert.equal((await x.call(valid)).status, 200); assert.equal(x.sent(), 1); });
test('rejects a different account, student role, and inaccessible child', async () => { for (const option of [{ email: 'other@example.com' }, { role: 'student' }, { student: false }]) { const x = setup(option); assert.equal((await x.call(valid)).status, 403); assert.equal(x.sent(), 0); } });
test('rejects malformed child and missing bearer', async () => { const x = setup(); assert.equal((await x.call({ childId: 'invalid' })).status, 400); assert.equal((await x.call(valid, '')).status, 401); assert.equal(x.sent(), 0); });
