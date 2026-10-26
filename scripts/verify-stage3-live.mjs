#!/usr/bin/env node
// Read-only integration checks against the existing project and DEMO identities.
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { createClient } from '../../frontend/node_modules/@supabase/supabase-js/dist/index.mjs';
const root = resolve(import.meta.dirname, '../..');
const parse = text => Object.fromEntries(text.split(/\r?\n/).map(line => line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/)).filter(Boolean).map(m => [m[1], m[2].replace(/^['"]|['"]$/g, '')]));
const env = { ...parse(await readFile(resolve(root, 'frontend/.env'), 'utf8')), ...parse(await readFile(resolve(root, 'frontend/.env.local'), 'utf8')) };
assert.equal(env.VITE_SUPABASE_URL,'https://nhwsgmijdsxzuxgpllhy.supabase.co');
const client = () => createClient(env.VITE_SUPABASE_URL,env.VITE_SUPABASE_ANON_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
const checked = (r,name) => { assert.equal(r.error,null,`${name}: ${r.error?.code} ${r.error?.message}`);return r.data; };
const codes = ['student_overview','students_by_course','students_by_subject','teachers_by_level','teachers_by_level_courses','teachers_by_course_schedule','students_by_sport','students_by_sport_level','students_by_sport_schedule','students_by_sport_schedule_teacher','students_by_transport','transport_and_dining'];
const admin=client(); const others=[];
const evidence={project:'nhwsgmijdsxzuxgpllhy',at:new Date().toISOString(),reports:[],access:[],modules:{}};
try {
 checked(await admin.auth.signInWithPassword({email:env.VITE_DEMO_SUPERADMIN_EMAIL,password:env.VITE_DEMO_SUPERADMIN_PASSWORD}),'admin login');
 const levels=checked(await admin.from('educational_levels').select('id,name').eq('is_active',true),'levels');
 const sports=checked(await admin.from('sports').select('id,name').eq('is_active',true),'sports');
 const routes=checked(await admin.from('transport_routes').select('id,route_number').eq('is_active',true),'routes');
 const report=async(code,filters)=>checked(await admin.rpc('get_admin_report',{p_report_code:code,p_filters:filters}),code);
 for(const code of codes) {
  const base=await report(code,{});const row={code,rows:base.length,queries:1,checks:[]};
  if(code!=='student_overview') {
   assert.equal((await report(code,{academic_year:1901})).length,0,code+' ignored year');row.queries++;
   const year=await report(code,{academic_year:2027});row.queries++;row.rows2027=year.length;
   const transport=['students_by_transport','transport_and_dining'].includes(code);
   const sport=code.startsWith('students_by_sport');
   const combinations=transport?routes.map(r=>({filters:{route_id:r.id},predicate:x=>x.route===r.route_number})):
    levels.flatMap(l=>sport?sports.map(s=>({filters:{level_id:l.id,sport_id:s.id},predicate:x=>x.educational_level===l.name&&x.sport===s.name})):[{filters:{level_id:l.id},predicate:x=>x.educational_level===l.name}]);
   for(const combo of combinations) {
    const actual=await report(code,{academic_year:2027,...combo.filters});row.queries++;
    const expected=year.filter(combo.predicate);
    assert.deepEqual(actual,expected,code+' filter differs from expected row intersection');
   }
   row.checks.push('year excludes absent cycle','every valid level/sport/route combination equals exact baseline intersection');
  } else row.checks.push('unfiltered summary; controls disabled in UI');
  evidence.reports.push(row);
 }
 for(const table of ['billing_values','invoices','invoice_items','transfer_submissions','transfer_receipts']) evidence.modules[table]=checked(await admin.from(table).select('*',{count:'exact',head:true}),table)??'available';
 for(const [key,role] of [['TEACHER','teacher'],['FAMILY','parent'],['STUDENT','student']]) {
  const c=client();others.push(c);
  checked(await c.auth.signInWithPassword({email:env['VITE_DEMO_'+key+'_EMAIL'],password:env['VITE_DEMO_'+key+'_PASSWORD']}),role+' login');
  const profile=checked(await c.auth.getUser(),role+' identity');assert(profile.user);
  const forums=checked(await c.from('forum_discussions').select('id'),role+' forum read');
  if(role!=='student')assert.equal(forums.length,0);
  const invoices=checked(await c.from('invoices').select('id'),role+' invoice read');
  if(role!=='parent')assert.equal(invoices.length,0);
  const denied=await c.rpc('billing_report',{p_start:'2027-01-01',p_end:'2027-12-31'});assert.equal(denied.error?.code,'42501');
  const deniedReport=await c.rpc('get_admin_report',{p_report_code:'students_by_course',p_filters:{}});assert.equal(deniedReport.error?.code,'42501');
  evidence.access.push({role,forumRows:forums.length,invoiceRows:invoices.length,adminReportsDenied:true});
 }
 const anon=client(); const denied=await anon.from('forum_discussions').select('id');assert(denied.error,'Anonymous forum read unexpectedly allowed');
 evidence.access.push({role:'anon',forumDenied:true});
 await writeFile(resolve(root,'backend/tmp/stage3-live-verification.local'),JSON.stringify(evidence,null,2));
 console.log(JSON.stringify(evidence,null,2));
} finally { await Promise.all([admin,...others].map(c=>c.auth.signOut({scope:'local'}))); }
