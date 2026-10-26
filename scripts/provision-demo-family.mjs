#!/usr/bin/env node
// Only the fixed DEMO identity and two existing fictitious 2027 students are writable.
// Server credentials are never copied to Vite. Re-running does not reset passwords.
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { createClient } from '../../frontend/node_modules/@supabase/supabase-js/dist/index.mjs';

const root = resolve(import.meta.dirname, '../..');
const backend = resolve(root, 'backend');
const localEnvPath = resolve(root, 'frontend/.env.local');
const credentialsPath = resolve(backend, 'tmp/family-credentials.local');
const email = 'familia.demo.2027@educar.example';
const fullName = 'Familia DEMO 2027';
const studentNumbers = ['DEMO-2027-A005', 'DEMO-2027-A010'];
const parse = text => Object.fromEntries(text.split(/\r?\n/).map(line => line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/)).filter(Boolean).map(m => [m[1], m[2].replace(/^['"]|['"]$/g, '')]));
const vars = parse(await readFile(resolve(root, 'frontend/.env'), 'utf8'));
const demo = parse(await readFile(localEnvPath, 'utf8'));
assert.equal(vars.VITE_SUPABASE_URL, 'https://nhwsgmijdsxzuxgpllhy.supabase.co', 'Unexpected Supabase target');
const options = { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } };
const client = key => createClient(vars.VITE_SUPABASE_URL, key, options);
const publicClient = client(vars.VITE_SUPABASE_ANON_KEY);
const checked = result => { if (result.error) throw new Error(`${result.error.code || 'API'}: ${result.error.message}`); return result.data; };
const login = async (connection, account, password) => checked(await connection.auth.signInWithPassword({ email: account, password }));
const adminSession = await login(publicClient, demo.VITE_DEMO_SUPERADMIN_EMAIL, demo.VITE_DEMO_SUPERADMIN_PASSWORD);
const adminProfile = checked(await publicClient.from('profiles').select('role,is_active,account_status').eq('id', adminSession.user.id).single());
assert.deepEqual(adminProfile, { role: 'superadmin', is_active: true, account_status: 'active' });
const students = checked(await publicClient.from('students').select('id,student_number,person_id').in('student_number', studentNumbers).eq('is_active', true));
assert.equal(students.length, 2, 'Two existing DEMO students required');
for (const student of students) {
  const person = checked(await publicClient.from('people').select('profile_id,email').eq('id', student.person_id).single());
  assert.equal(person.profile_id, null, 'Refusing a student linked to a real Auth identity');
  assert.match(person.email, /^alumno\d+@educar\.example$/);
  const enrollment = checked(await publicClient.from('student_enrollments').select('id').eq('student_id', student.id).eq('academic_year', 2027).eq('is_active', true));
  assert.equal(enrollment.length, 1, 'Active 2027 enrollment required');
}

if (process.argv.includes('--apply')) {
  await mkdir(resolve(backend, 'tmp'), { recursive: true });
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY || (await readFile(resolve(backend, 'tmp/server-key.local'), 'utf8')).trim();
  const server = client(key);
  // This snapshot protects the additive DEMO operation only; it is not a database backup.
  const snapshot = { project: 'nhwsgmijdsxzuxgpllhy', createdAt: new Date().toISOString(), tables: {} };
  for (const table of ['profiles', 'people', 'student_guardians']) snapshot.tables[table] = checked(await server.from(table).select('*'));
  await writeFile(resolve(backend, `tmp/family-before-${Date.now()}.local`), JSON.stringify(snapshot, null, 2), { mode: 0o600 });
  const existing = snapshot.tables.profiles.find(profile => profile.email.toLowerCase() === email);
  let account, password;
  if (existing) {
    account = checked(await server.auth.admin.getUserById(existing.id)).user;
    assert.equal(existing.role, 'parent', 'Existing account has another role; refusing to modify it');
    assert.equal(account.app_metadata.demo_cycle, 2027, 'Existing identity is not marked DEMO');
    const saved = JSON.parse(await readFile(credentialsPath, 'utf8'));
    assert.equal(saved.email, email);
    assert.equal(saved.userId, account.id);
    password = saved.password;
  } else {
    password = randomBytes(24).toString('base64url');
    account = checked(await server.auth.admin.createUser({ email, password, email_confirm: true,
      user_metadata: { full_name: fullName }, app_metadata: { demo_cycle: 2027 } })).user;
    // Save immediately so a partial failure can be diagnosed without resetting Auth.
    await writeFile(credentialsPath, JSON.stringify({ email, password, userId: account.id }), { mode: 0o600 });
    checked(await server.from('profiles').update({ role: 'parent', is_active: true, account_status: 'active', activated_at: new Date().toISOString() }).eq('id', account.id).select('id').single());
  }
  const provisioned = checked(await publicClient.functions.invoke('admin-provision-user', { body: { email, full_name: fullName, role: 'parent' } }));
  assert.equal(provisioned.account.id, account.id);
  const guardian = checked(await server.from('people').select('id').eq('profile_id', account.id).single());
  // The live link_student_guardian RPC has an ambiguous guardian_person_id.
  // This server-only DEMO operation stays additive and preserves primary tutors.
  for (const student of students) checked(await server.from('student_guardians').upsert({
    student_id: student.id, guardian_person_id: guardian.id, relationship_type: 'tutor demo', is_primary: false, is_active: true,
  }, { onConflict: 'student_id,guardian_person_id,relationship_type' }));
  console.log('DEMO Auth parent provisioned; two existing fictitious 2027 children linked.');
}

const saved = JSON.parse(await readFile(credentialsPath, 'utf8'));
assert.equal(saved.email, email);
const family = client(vars.VITE_SUPABASE_ANON_KEY);
const session = await login(family, email, saved.password);
assert.equal(session.user.id, saved.userId);
const profile = checked(await family.from('profiles').select('id,role,is_active,account_status'));
assert.equal(profile.length, 1, 'Family must see only its profile');
assert.equal(profile[0].role, 'parent');
assert.equal(profile[0].account_status, 'active');
assert.equal(profile[0].is_active, true);
const expected = students.map(row => row.id).sort();
const visible = checked(await family.from('students').select('id'));
assert.deepEqual(visible.map(row => row.id).sort(), expected, 'RLS must expose exactly two children');
const links = checked(await family.from('student_guardians').select('student_id').eq('is_active', true));
assert.deepEqual(links.map(row => row.student_id).sort(), expected);
const counts = {};
for (const table of ['student_enrollments', 'student_subject_enrollments', 'student_sport_enrollments', 'student_transport_enrollments', 'student_dining_enrollments']) {
  const rows = checked(await family.from(table).select('id,student_id').eq('is_active', true));
  assert(rows.every(row => expected.includes(row.student_id)), `${table} leaked another student`);
  assert(students.every(student => rows.some(row => row.student_id === student.id)), `${table} missing child data`);
  counts[table] = rows.length;
}
const unrelated = checked(await publicClient.from('students').select('id').not('id', 'in', `(${expected.join(',')})`).limit(1));
assert.equal(unrelated.length, 1);
assert.deepEqual(checked(await family.from('students').select('id').eq('id', unrelated[0].id)), []);
for (const [rpc, args] of [
  ['approve_enrollment_request', { p_request_id: unrelated[0].id, p_course_id: unrelated[0].id }],
  ['get_admin_report', { p_report_code: 'student_overview', p_filters: {} }],
]) {
  const result = await family.rpc(rpc, args);
  assert.equal(result.error?.code, '42501', `${rpc} must refuse a parent`);
}
const evidence = { project: 'nhwsgmijdsxzuxgpllhy', verifiedAt: new Date().toISOString(), role: 'parent', students: studentNumbers, counts, checks: ['Auth password login', 'own profile only', 'exactly two students and links', 'services and academic enrollments scoped', 'unrelated child hidden', 'admin RPC denied'] };
await writeFile(resolve(backend, 'tmp/family-verification.local'), JSON.stringify(evidence, null, 2));
if (process.argv.includes('--enable-footer')) {
  let text = await readFile(localEnvPath, 'utf8');
  for (const [name, value] of Object.entries({ VITE_DEMO_FAMILY_EMAIL: email, VITE_DEMO_FAMILY_PASSWORD: saved.password, VITE_DEMO_FAMILY_VERIFIED: 'true' })) {
    text = text.replace(new RegExp(`^${name}=.*(?:\\r?\\n|$)`, 'gm'), '');
    text = `${text.trimEnd()}\n${name}=${value}\n`;
  }
  await writeFile(localEnvPath, text);
}
await family.auth.signOut({ scope: 'local' });
await publicClient.auth.signOut({ scope: 'local' });
console.log(JSON.stringify(evidence, null, 2));
