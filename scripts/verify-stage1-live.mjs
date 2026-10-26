#!/usr/bin/env node
// --write-demo applies only the fixed academic DEMO fixtures; default is read-only.
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { createClient } from '../../frontend/node_modules/@supabase/supabase-js/dist/index.mjs';

const root = resolve(import.meta.dirname, '../..');
const parse = text => Object.fromEntries(text.split(/\r?\n/).map(line => line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/)).filter(Boolean).map(m => [m[1], m[2].replace(/^['"]|['"]$/g, '')]));
const env = { ...parse(await readFile(resolve(root, 'frontend/.env'), 'utf8')), ...parse(await readFile(resolve(root, 'frontend/.env.local'), 'utf8')) };
assert.equal(env.VITE_SUPABASE_URL, 'https://nhwsgmijdsxzuxgpllhy.supabase.co');
const makeClient = () => createClient(env.VITE_SUPABASE_URL, env.VITE_SUPABASE_ANON_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
const checked = (result, operation) => { if (result.error) throw new Error(`${operation}: ${result.error.code || 'API'} ${result.error.message}`); return result.data; };
const admin = makeClient();
const family = makeClient();
const write = process.argv.includes('--write-demo');
const approvalId = '5d04739e-13a2-4f36-acf5-f536abc093d3';
const pendingId = '43965105-2910-4f36-b37c-8625d5c6624f';
const rejectedId = 'cf0cc745-eae6-436a-83fb-72416cf46fc7';
const serviceDate = '2027-04-01';
const evidence = { project: 'nhwsgmijdsxzuxgpllhy', checkedAt: new Date().toISOString(), mode: write ? 'controlled DEMO writes' : 'read-only', checks: {} };
try {
  const session = checked(await admin.auth.signInWithPassword({ email: env.VITE_DEMO_SUPERADMIN_EMAIL, password: env.VITE_DEMO_SUPERADMIN_PASSWORD }), 'admin login');
  const profile = checked(await admin.from('profiles').select('role,is_active,account_status').eq('id', session.user.id).single(), 'admin profile');
  assert.deepEqual(profile, { role: 'superadmin', is_active: true, account_status: 'active' });
  const listRequests = async () => checked(await admin.rpc('list_enrollment_requests', { p_status: null }), 'list requests');
  const before = await listRequests();
  const request = before.find(row => row.id === approvalId);
  assert(request && request.notes === 'DEMO-2027-REQUEST-APPROVED' && request.student_dni === '47100002' && request.academic_year === 2027, 'Unexpected approval fixture');
  const course = checked(await admin.from('courses').select('id').eq('code', 'DEMO-27-PRI-A').eq('academic_year', 2027).eq('is_active', true).single(), 'DEMO course');
  if (write) {
    const args = { p_request_id: approvalId, p_course_id: course.id };
    const first = checked(await admin.rpc('approve_enrollment_request', args), 'approve DEMO');
    assert.equal(first.status, 'approved');
    const repeat = checked(await admin.rpc('approve_enrollment_request', args), 'repeat approval');
    assert.deepEqual(repeat, first, 'Approval must return the same student/enrollment');
  }
  const requests = await listRequests();
  const approved = requests.find(row => row.id === approvalId);
  assert.equal(approved.status, 'approved');
  assert(approved.student_id && approved.enrollment_id);
  assert.equal(requests.find(row => row.id === pendingId).status, 'pending');
  assert.equal(requests.find(row => row.id === rejectedId).status, 'rejected');
  const people = checked(await admin.from('people').select('id').eq('dni', '47100002'), 'approved person');
  assert.equal(people.length, 1);
  const students = checked(await admin.from('students').select('id').eq('person_id', people[0].id), 'approved student');
  assert.deepEqual(students.map(row => row.id), [approved.student_id]);
  const enrollments = checked(await admin.from('student_enrollments').select('id,course_id').eq('student_id', approved.student_id).eq('academic_year', 2027).eq('is_active', true), 'approved enrollment');
  assert.deepEqual(enrollments, [{ id: approved.enrollment_id, course_id: course.id }]);
  evidence.checks.approval = { requestId: approvalId, status: approved.status, studentId: approved.student_id, enrollmentId: approved.enrollment_id, matchingPeople: people.length, matchingStudents: students.length, activeEnrollments: enrollments.length };

  const child = checked(await admin.from('students').select('id').eq('student_number', 'DEMO-2027-A005').single(), 'dining child');
  const dining = checked(await admin.from('student_dining_enrollments').select('id').eq('student_id', child.id).eq('academic_year', 2027).eq('is_active', true).single(), 'dining enrollment');
  if (write) {
    const args = { p_dining_enrollment_id: dining.id, p_service_date: serviceDate };
    const first = checked(await admin.rpc('record_dining_usage', { ...args, p_used: true }), 'create dining usage');
    const second = checked(await admin.rpc('record_dining_usage', { ...args, p_used: false }), 'update dining usage');
    assert.equal(first.used, true);
    assert.equal(second.used, false);
    assert.equal(second.id, first.id, 'Dining update must reuse the row');
  }
  const usage = checked(await admin.from('dining_usage').select('id,used').eq('dining_enrollment_id', dining.id).eq('service_date', serviceDate), 'persisted dining usage');
  assert.equal(usage.length, 1);
  assert.equal(usage[0].used, false);
  evidence.checks.dining = { enrollmentId: dining.id, serviceDate, rows: usage.length, finalUsed: usage[0].used };

  const parent = checked(await admin.from('profiles').select('id').eq('email', 'familia.demo.2027@educar.example').eq('role', 'parent').single(), 'parent profile');
  const guardian = checked(await admin.from('people').select('id').eq('profile_id', parent.id).single(), 'guardian person');
  if (write) {
    const args = { p_student_id: child.id, p_guardian_profile_id: parent.id, p_relationship_type: 'tutor demo', p_is_primary: false };
    const first = checked(await admin.rpc('link_student_guardian', args), 'guardian RPC');
    const second = checked(await admin.rpc('link_student_guardian', args), 'repeat guardian RPC');
    assert.equal(first.id, second.id);
  }
  const adminLinks = checked(await admin.from('student_guardians').select('id,student_id').eq('guardian_person_id', guardian.id).eq('is_active', true), 'guardian links');
  assert.equal(adminLinks.length, 2);
  const parentSession = checked(await family.auth.signInWithPassword({ email: env.VITE_DEMO_FAMILY_EMAIL, password: env.VITE_DEMO_FAMILY_PASSWORD }), 'family login');
  assert.equal(parentSession.user.id, parent.id);
  const familyStudents = checked(await family.from('students').select('id,student_number'), 'family students');
  assert.deepEqual(familyStudents.map(row => row.student_number).sort(), ['DEMO-2027-A005', 'DEMO-2027-A010']);
  const familyLinks = checked(await family.from('student_guardians').select('student_id').eq('is_active', true), 'family RLS links');
  assert.equal(familyLinks.length, 2);
  assert.deepEqual(checked(await family.from('students').select('id').eq('id', approved.student_id), 'unrelated student hidden'), []);
  // These deny cases must fail before any write; they use complete valid RPC payloads.
  for (const [name, args] of [
    ['link_student_guardian', { p_student_id: approved.student_id, p_guardian_profile_id: parent.id, p_relationship_type: 'tutor demo', p_is_primary: false }],
    ['approve_enrollment_request', { p_request_id: pendingId, p_course_id: course.id }],
    ['record_dining_usage', { p_dining_enrollment_id: dining.id, p_service_date: serviceDate, p_used: true }],
  ]) {
    const result = await family.rpc(name, args);
    assert.equal(result.error?.code, '42501', `${name} must deny parent`);
  }
  evidence.checks.family = { children: familyStudents.map(row => row.student_number), links: familyLinks.length, unrelatedStudentHidden: true, adminRPCsDenied: 3 };
  const schedules = checked(await admin.from('academic_schedules').select('id,course_id,course_subject_id,academic_year,day_of_week,starts_at,ends_at').eq('academic_year', 2027).eq('is_active', true), 'teacher agenda');
  const subjects = checked(await admin.from('course_subjects').select('id,teacher_id').eq('academic_year', 2027).eq('is_active', true), 'teacher assignments');
  const teachers = new Map(subjects.map(row => [row.id, row.teacher_id]));
  const conflicts = schedules.flatMap((a, index) => schedules.slice(index + 1).filter(b => a.course_id !== b.course_id && a.day_of_week === b.day_of_week && teachers.get(a.course_subject_id) && teachers.get(a.course_subject_id) === teachers.get(b.course_subject_id) && a.starts_at < b.ends_at && b.starts_at < a.ends_at));
  assert.equal(conflicts.length, 0);
  evidence.checks.teacherAgenda = { schedules: schedules.length, conflictingPairs: conflicts.length };
  await writeFile(resolve(root, 'backend/tmp/stage1-live-verification.local'), JSON.stringify(evidence, null, 2));
  console.log(JSON.stringify(evidence, null, 2));
} finally {
  await admin.auth.signOut({ scope: 'local' });
  await family.auth.signOut({ scope: 'local' });
}
