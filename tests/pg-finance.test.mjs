import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync,spawn} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';
const bin=process.env.TEST_PG_BIN || 'C:/Program Files/PostgreSQL/18/bin';
const executable=name=>path.join(bin,`${name}${process.platform==='win32'?'.exe':''}`);
const id=n=>`81000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
test('actual PostgreSQL financial migrations enforce family RLS and atomic partial payments',async()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'educar-finance-test-'));const data=path.join(root,'data');let started=false;let primary;
 const server=net.createServer();await new Promise(r=>server.listen(0,'127.0.0.1',r));const port=server.address().port;await new Promise(r=>server.close(r));
 const run=(name,args,input)=>{const result=spawnSync(executable(name),args,{input,encoding:'utf8',timeout:60000,...(name==='pg_ctl'?{stdio:'ignore'}:{})});if(result.error)throw result.error;assert.equal(result.status,0,`${name}: ${(result.stderr||result.stdout||'process failed').slice(-1800)}`);return (result.stdout||'').trim();};
 const args=['-h','127.0.0.1','-p',String(port),'-U','fixture_admin','-d','postgres','-X','-q','-t','-A','-v','ON_ERROR_STOP=1'];
 const sql=text=>run('psql',args,text);
 const as=(n,text)=>sql(`set role authenticated;select set_config('request.jwt.claim.sub','${id(n)}',false);select set_config('request.jwt.claim.role','authenticated',false);${text}`).split('\n').at(-1);
 const denied=(n,text)=>{const result=spawnSync(executable('psql'),args,{input:`set role authenticated;select set_config('request.jwt.claim.sub','${id(n)}',false);${text}`,encoding:'utf8',timeout:10000});assert.notEqual(result.status,0,'operation unexpectedly succeeded');return result.stderr;};
 try{
  run('initdb',['-D',data,'-U','fixture_admin','-A','trust','--encoding=UTF8','--no-locale']);
  started=true;run('pg_ctl',['-D',data,'-l',path.join(root,'server.log'),'-o',`-h 127.0.0.1 -p ${port}`,'-w','start']);started=true;
  sql(fs.readFileSync('tests/pg-platform-fixture.sql','utf8'));
  for(const file of fs.readdirSync('supabase/migrations').filter(x=>/^2026100[89]/.test(x)).sort())sql(fs.readFileSync(`supabase/migrations/${file}`,'utf8'));
  sql(`insert into profiles(id,full_name,email,role) values('${id(1)}','Parent','parent@example.test','guardian'),('${id(2)}','Admin','admin@example.test','admin');insert into people(id,profile_id,first_name,last_name) values('${id(11)}','${id(1)}','Parent','Fixture'),('${id(12)}',null,'Child','Fixture'),('${id(13)}',null,'Foreign','Fixture');insert into students(id,person_id) values('${id(21)}','${id(12)}'),('${id(22)}','${id(13)}');insert into student_guardians values('${id(21)}','${id(11)}',true);insert into invoices(id,student_id,period,due_date) values('${id(31)}','${id(21)}','2026-10-01','2026-10-10'),('${id(32)}','${id(22)}','2026-10-01','2026-10-10');insert into invoice_items(id,invoice_id,concept,label,amount_cents) values('${id(41)}','${id(31)}','tuition','Tuition',10000),('${id(42)}','${id(32)}','tuition','Tuition',10000);insert into storage.objects(bucket_id,name,owner_id) values('transfer-receipts','${id(1)}/test.pdf','${id(1)}'),('transfer-receipts','${id(1)}/unused.pdf','${id(1)}');`);
  assert.equal(as(1,'select count(*) from invoices;'),'1');
  const submit=(invoice=id(31),item=id(41),amount=5000,ref='BANK')=>`select submit_transfer('${invoice}',array['${item}']::uuid[],${amount},'${ref}','${id(1)}/test.pdf','test.pdf');`;
  assert.match(denied(1,submit(id(32),id(42))),/Invoice access denied/);
  assert.match(denied(1,submit(id(31),id(42))),/Invalid selected/);
  const operation=as(1,submit());assert.match(operation,/^[\da-f-]{36}$/);
  assert.equal(as(1,submit()),operation);assert.equal(as(1,'select paid_cents from invoice_items;'),'0');
  assert.equal(as(1,`select count(*) from transfer_submissions;`),'1');
  assert.match(denied(1,submit(id(31),id(41),4000)),/different operation/);
  assert.equal(as(1,`delete from storage.objects where name='${id(1)}/test.pdf' returning name;`),'authenticated');
  assert.equal(sql(`select count(*) from storage.objects where name='${id(1)}/test.pdf';`),'1');
  as(1,`delete from storage.objects where name='${id(1)}/unused.pdf';`);assert.equal(sql(`select count(*) from storage.objects where name='${id(1)}/unused.pdf';`),'0');
  as(2,`select review_transfer('${operation}',true);`);assert.equal(as(1,'select paid_cents from invoice_items;'),'5000');
  assert.match(denied(2,`select review_transfer('${operation}',true);`),/already reviewed/);
  sql(`update profiles set is_active=false where id='${id(1)}';`);assert.equal(as(1,'select count(*) from invoices;'),'0');assert.match(denied(1,submit()),/Invoice access denied/);
  sql(`update profiles set is_active=true where id='${id(1)}';`);
  as(2,`insert into billing_values(concept,label,amount_cents,effective_from) values('tuition','New tuition',12000,'2026-11-01');select issue_monthly_invoice('${id(21)}','2026-11-01','2026-11-10');`);
  assert.equal(sql(`select amount_cents from invoice_items where invoice_id='${id(31)}';`),'10000');
  const pendingInvoice=sql(`select id from invoices where student_id='${id(21)}' and period='2026-11-01';`);
  const pendingItem=sql(`select id from invoice_items where invoice_id='${pendingInvoice}';`);
  sql(`insert into storage.objects(bucket_id,name,owner_id) values('transfer-receipts','${id(1)}/race.pdf','${id(1)}'),('transfer-receipts','${id(1)}/extra.pdf','${id(1)}');`);
  const raceSubmit=`select submit_transfer('${pendingInvoice}',array['${pendingItem}']::uuid[],1000,'RACE','${id(1)}/race.pdf','race.pdf');`;
  const concurrent=(n,text)=>new Promise((resolve,reject)=>{const child=spawn(executable('psql'),args,{stdio:['pipe','pipe','pipe']});let stdout='',stderr='';const timer=setTimeout(()=>{child.kill();reject(new Error('Concurrent SQL timed out'));},15000);child.stdout.on('data',x=>stdout+=x);child.stderr.on('data',x=>stderr+=x);child.on('error',reject);child.on('close',code=>{clearTimeout(timer);resolve({code,stdout,stderr});});child.stdin.end(`set application_name='finance-first';set role authenticated;select set_config('request.jwt.claim.sub','${id(n)}',false);${text}`);});
  const sleeping=async()=>{for(let attempts=0;attempts<20;attempts++){if(sql("select count(*) from pg_stat_activity where application_name='finance-first' and wait_event='PgSleep';")==='1')return;await new Promise(r=>setTimeout(r,50));}throw new Error('First connection never held transaction lock');};
  const first=concurrent(1,`begin;${raceSubmit}select pg_sleep(3);commit;`);await sleeping();
  const second=concurrent(1,raceSubmit);const both=await Promise.all([first,second]);assert.ok(both.every(x=>x.code===0));assert.equal(sql("select count(*) from transfer_submissions where reference='RACE';"),'1');
  const raceId=sql("select id from transfer_submissions where reference='RACE';");
  const reviewing=concurrent(2,`begin;select review_transfer('${raceId}',true);select pg_sleep(3);commit;`);await sleeping();
  const attachment=concurrent(1,`select attach_transfer_receipt('${raceId}','${id(1)}/extra.pdf','extra.pdf');`);
  const reviewed=await reviewing;assert.equal(reviewed.code,0);const attached=await attachment;assert.notEqual(attached.code,0);assert.match(attached.stderr,/Submission access denied/);
  assert.equal(sql(`select paid_cents from invoice_items where id='${pendingItem}';`),'1000');
  console.log('PG18 financial migrations, authenticated RLS, partial allocation, idempotency and two-connection locking PASS. Supabase platform compatibility fixtures only.');
 }catch(error){primary=error;throw error;
 }finally{
  try {
  if(started)run('pg_ctl',['-D',data,'-m','immediate','-w','stop']);
  const resolved=path.resolve(root);assert.ok(resolved.startsWith(path.resolve(os.tmpdir())+path.sep)&&path.basename(resolved).startsWith('educar-finance-test-'));
  fs.rmSync(resolved,{recursive:true,force:true,maxRetries:10,retryDelay:200});assert.equal(fs.existsSync(resolved),false);console.log('Owned disposable cluster stopped and verified temporary directory removed.');
  }catch(cleanup){if(primary)console.error('Cleanup failed after primary error:',cleanup.message);else throw cleanup;}
 }
});
