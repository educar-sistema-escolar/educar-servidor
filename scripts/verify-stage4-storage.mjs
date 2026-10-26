// Real Auth + Storage + RPC workflow, using existing DEMO family; no service key.
// Retains two clearly fictitious receipts as presentation evidence. Idempotent.
import assert from 'node:assert/strict';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
const root = new URL('../../', import.meta.url);
const env = {};
for (const name of ['.env', '.env.local']) {
  const source = await readFile(new URL(`frontend/${name}`, root), 'utf8');
  for (const line of source.split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (m) env[m[1]] = m[2].replace(/^['"]|['"]$/g, '');
  }
}
assert.equal(env.VITE_SUPABASE_URL, 'https://nhwsgmijdsxzuxgpllhy.supabase.co');
const base = env.VITE_SUPABASE_URL;
const key = env.VITE_SUPABASE_ANON_KEY;
async function request(path, token, { method = 'GET', body, binary = false } = {}) {
  const response = await fetch(base + path, {
    method, signal: AbortSignal.timeout(25000),
    headers: { apikey: key, Authorization: `Bearer ${token || key}`, ...(body ? { 'Content-Type': binary ? 'application/pdf' : 'application/json' } : {}) },
    body: body ? (binary ? body : JSON.stringify(body)) : undefined,
  });
  const data = await response.text();
  return { status: response.status, data: data ? (() => { try { return JSON.parse(data); } catch { return data; } })() : null };
}
const ok = (r, label) => { assert(r.status >= 200 && r.status < 300, `${label}: HTTP ${r.status} ${JSON.stringify(r.data)}`); return r.data; };
async function login(role) {
  return ok(await request('/auth/v1/token?grant_type=password', null, { method: 'POST', body: { email: env[`VITE_DEMO_${role}_EMAIL`], password: env[`VITE_DEMO_${role}_PASSWORD`] } }), `${role} login`);
}
const sessions = [];
const evidence = { project: 'nhwsgmijdsxzuxgpllhy', at: new Date().toISOString(), receipts: [] };
function pdf(label) {
  const stream = `BT /F1 16 Tf 50 760 Td (DEMO 2027 - SIN VALOR FISCAL) Tj 0 -30 Td (${label}) Tj 0 -30 Td (Archivo ficticio. No acredita un pago real.) Tj ET`;
  const objects = ['<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Kids [3 0 R] /Count 1 >>','<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>','<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',`<< /Length ${Buffer.byteLength(stream)} >>\nstream\n${stream}\nendstream`];
  let text = '%PDF-1.4\n'; const offsets = [0];
  objects.forEach((o, i) => { offsets.push(Buffer.byteLength(text)); text += `${i + 1} 0 obj\n${o}\nendobj\n`; });
  const xref = Buffer.byteLength(text);
  text += `xref\n0 6\n0000000000 65535 f \n${offsets.slice(1).map(o => `${String(o).padStart(10,'0')} 00000 n \n`).join('')}trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return Buffer.from(text);
}
try {
  const admin = await login('SUPERADMIN'); sessions.push(admin);
  const family = await login('FAMILY'); sessions.push(family);
  const foreign = await login('STUDENT'); sessions.push(foreign);
  const invoices = ok(await request('/rest/v1/invoices?select=id,student_id,period&order=period', family.access_token), 'family invoices');
  assert.equal(invoices.length, 4);
  for (const [period, reference, approve] of [['2027-03-01','DEMO-2027-PAGO-MARZO',true],['2027-04-01','DEMO-2027-REVISION-ABRIL',false]]) {
    const invoice = invoices.find(i => i.period === period);
    assert(invoice);
    const items = ok(await request(`/rest/v1/invoice_items?invoice_id=eq.${invoice.id}&select=id,amount_cents,paid_cents`, family.access_token), 'invoice items');
    const path = `${family.user.id}/etapa4-${reference}.pdf`;
    const bytes = pdf(reference);
    const filename = `${reference}.pdf`;
    const existing = ok(await request(`/rest/v1/transfer_submissions?reference=eq.${reference}&select=id,status`, family.access_token),'existing transfer');
    let transfer = existing[0];
    if (!transfer) {
      const upload = await request(`/storage/v1/object/transfer-receipts/${path}`,family.access_token,{method:'POST',body:bytes,binary:true});
      if (upload.status === 400 && upload.data?.statusCode === '409') {
        ok(await request(`/storage/v1/object/authenticated/transfer-receipts/${path}`,family.access_token),'existing upload');
      } else ok(upload,'binary upload');
      const body = {p_invoice:invoice.id,p_items:items.map(i=>i.id),p_amount:items.reduce((sum,i)=>sum+Number(i.amount_cents)-Number(i.paid_cents),0),p_reference:reference,p_path:path,p_filename:filename};
      const id = ok(await request('/rest/v1/rpc/submit_transfer',family.access_token,{method:'POST',body}),'submit transfer');
      assert.equal(ok(await request('/rest/v1/rpc/submit_transfer',family.access_token,{method:'POST',body}),'repeat submit'),id);
      transfer = {id,status:'pending'};
    }
    if (approve && transfer.status === 'pending') ok(await request('/rest/v1/rpc/review_transfer',admin.access_token,{method:'POST',body:{p_submission:transfer.id,p_approve:true}}),'approve fictitious transfer');
    const receipt = ok(await request(`/rest/v1/transfer_receipts?submission_id=eq.${transfer.id}&select=id,storage_path`,admin.access_token),'admin receipt');
    assert.equal(receipt[0]?.storage_path,path);
    for (const [name, session] of [['family',family],['admin',admin]]) {
      const signed = ok(await request(`/storage/v1/object/sign/transfer-receipts/${path}`,session.access_token,{method:'POST',body:{expiresIn:60}}),`${name} signed URL`);
      const url = base + '/storage/v1' + signed.signedURL;
      const download = await fetch(url,{signal:AbortSignal.timeout(25000)});
      assert.equal(download.status,200);
      assert.deepEqual(Buffer.from(await download.arrayBuffer()),bytes);
    }
    const deniedSign = await request(`/storage/v1/object/sign/transfer-receipts/${path}`,foreign.access_token,{method:'POST',body:{expiresIn:60}});
    const deniedRead = await request(`/storage/v1/object/authenticated/transfer-receipts/${path}`,foreign.access_token);
    const deniedPublic = await request(`/storage/v1/object/public/transfer-receipts/${path}`,null);
    assert(deniedSign.status >= 400 && deniedRead.status >= 400 && deniedPublic.status >= 400);
    const after = ok(await request(`/rest/v1/invoice_items?invoice_id=eq.${invoice.id}&select=amount_cents,paid_cents`,admin.access_token),'payment state');
    assert(after.every(i=>approve ? i.paid_cents===i.amount_cents : Number(i.paid_cents)===0));
    evidence.receipts.push({invoice:invoice.id,transfer:transfer.id,path,bytes:bytes.length,status:approve?'approved':'pending',binaryVerified:true,familyAndAdminSignedDownload:true,foreignSignStatus:deniedSign.status,foreignReadStatus:deniedRead.status,publicReadStatus:deniedPublic.status});
  }
  // Upload a disposable unattached file and remove it through the authorized policy.
  const temp = `${family.user.id}/etapa4-temporary.pdf`;
  ok(await request(`/storage/v1/object/transfer-receipts/${temp}`,family.access_token,{method:'POST',body:pdf('TEMPORARY'),binary:true}),'temporary upload');
  ok(await request('/storage/v1/object/transfer-receipts',family.access_token,{method:'DELETE',body:{prefixes:[temp]}}),'temporary removal');
  assert((await request(`/storage/v1/object/authenticated/transfer-receipts/${temp}`,family.access_token)).status>=400);
  evidence.temporaryRemoved=true;
  evidence.signedUrlLimit='Signed URLs are bearer links valid for 60 seconds; keep private. Foreign users cannot mint a URL or read the private object directly.';
  await mkdir(new URL('backend/tmp/',root),{recursive:true});
  await writeFile(new URL('backend/tmp/stage4-storage.json',root),JSON.stringify(evidence,null,2));
  console.log(JSON.stringify(evidence,null,2));
} finally {
  await Promise.allSettled(sessions.map(s=>request('/auth/v1/logout?scope=local',s.access_token,{method:'POST'})));
}
