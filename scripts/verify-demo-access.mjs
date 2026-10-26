#!/usr/bin/env node
/** Read-only smoke checks against the project's real test accounts. Never logs secrets. */
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { createClient } from '../../frontend/node_modules/@supabase/supabase-js/dist/index.mjs';
const root = resolve(import.meta.dirname, '../..');
const parse = text => Object.fromEntries(text.split(/\r?\n/).map(line => line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/)).filter(Boolean).map(m => [m[1], m[2].replace(/^['"]|['"]$/g, '')]));
const env = { ...parse(await readFile(resolve(root,'frontend/.env'),'utf8')), ...parse(await readFile(resolve(root,'frontend/.env.local'),'utf8')) };
assert.equal(env.VITE_SUPABASE_URL, 'https://nhwsgmijdsxzuxgpllhy.supabase.co');
const checked = result => { if(result.error) throw new Error(`${result.error.code || 'API'}: ${result.error.message}`); return result.data; };
const evidence = {project:'nhwsgmijdsxzuxgpllhy', verifiedAt:new Date().toISOString(), roles:{}, reports:[]};
for (const [name, role] of [['SUPERADMIN','superadmin'],['TEACHER','teacher'],['STUDENT','student'],['FAMILY','parent']]) {
  assert(env[`VITE_DEMO_${name}_EMAIL`] && env[`VITE_DEMO_${name}_PASSWORD`], `${name}: credentials missing`);
  const client=createClient(env.VITE_SUPABASE_URL,env.VITE_SUPABASE_ANON_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
  const session=checked(await client.auth.signInWithPassword({email:env[`VITE_DEMO_${name}_EMAIL`],password:env[`VITE_DEMO_${name}_PASSWORD`]}));
  const profile=checked(await client.from('profiles').select('role,is_active,account_status').eq('id',session.user.id).single());
  assert.deepEqual(profile,{role,is_active:true,account_status:'active'});
  const visible=checked(await client.from('students').select('id'));
  if(role==='student') assert.equal(visible.length,1,'Student must see exactly their own record');
  if(role==='parent') assert.equal(visible.length,2,'Family must see exactly two children');
  if(role==='teacher') {
    const person=checked(await client.from('people').select('id').eq('profile_id',session.user.id).single());
    const teacher=checked(await client.from('teachers').select('id').eq('person_id',person.id).single());
    const assignments=checked(await client.from('course_subjects').select('id').eq('teacher_id',teacher.id).eq('is_active',true));
    assert(assignments.length>0,'Teacher must have active teaching assignments');
  }
  if(role==='superadmin') {
    const level=checked(await client.from('educational_levels').select('id').order('sort_order').limit(1))[0];
    const sport=checked(await client.from('sports').select('id').like('code','DEMO-%').limit(1))[0];
    const route=checked(await client.from('transport_routes').select('id').like('name','DEMO %').limit(1))[0];
    assert(level && sport && route,'DEMO filter fixtures required');
    const filters=[{}, {academic_year:2027}, {level_id:level.id}, {sport_id:sport.id}, {route_id:route.id}, {academic_year:2027,level_id:level.id,sport_id:sport.id,route_id:route.id}];
    const codes=['student_overview','students_by_course','students_by_subject','teachers_by_level','teachers_by_level_courses','teachers_by_course_schedule','students_by_sport','students_by_sport_level','students_by_sport_schedule','students_by_sport_schedule_teacher','students_by_transport','transport_and_dining'];
    for(const code of codes) {
      const results=await Promise.all(filters.map(async filter=>checked(await client.rpc('get_admin_report',{p_report_code:code,p_filters:filter}))));
      assert(results.every(Array.isArray));
      assert(results[0].length>0, `${code}: expected DEMO rows`);
      for(const row of results[1]) if('academic_year' in row) assert.equal(Number(row.academic_year),2027);
      evidence.reports.push({code,rows:results.map(rows=>rows.length)});
    }
  } else {
    const result=await client.rpc('get_admin_report',{p_report_code:'student_overview',p_filters:{}});
    assert.equal(result.error?.code,'42501','Non-admin reports must be denied');
    const provisioning=await client.functions.invoke('admin-provision-user',{body:{email:'uncreated@example.test',full_name:'Forbidden Fixture',role:'parent'}});
    assert.equal(provisioning.error?.context?.status,403,'Non-admin provisioning must be denied');
  }
  evidence.roles[role]={active:true,visibleStudents:visible.length};
  await client.auth.signOut({ scope: 'local' });
}
await writeFile(resolve(root,'backend/tmp/access-verification.local'),JSON.stringify(evidence,null,2));
console.log(JSON.stringify(evidence,null,2));
