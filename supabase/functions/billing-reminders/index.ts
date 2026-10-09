import { createClient } from 'npm:@supabase/supabase-js@2';
const required=(key:string)=>{const value=Deno.env.get(key);if(!value)throw new Error(`Missing server configuration: ${key}`);return value;};
Deno.serve(async(request)=>{
 if(request.method!=='POST')return new Response('Method not allowed',{status:405});
 const secret=Deno.env.get('BILLING_CRON_SECRET');if(!secret||request.headers.get('Authorization')!==`Bearer ${secret}`)return new Response('Unauthorized',{status:401});
 try {
 const client=createClient(required('SUPABASE_URL'),required('SUPABASE_SERVICE_ROLE_KEY'));const apiKey=required('RESEND_API_KEY');const sender=required('BILLING_FROM_EMAIL');
 const date=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Argentina/Buenos_Aires',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 const prepared=await client.rpc('prepare_billing_reminders',{p_date:date});if(prepared.error)throw prepared.error;
 const {data:queue,error}=await client.from('billing_reminders').select('*').eq('status','ready').eq('reminder_date',date).limit(50);if(error)throw error;
 let sent=0;
 for(const reminder of queue??[]){
  const claimed=await client.from('billing_reminders').update({status:'sending'}).eq('id',reminder.id).eq('status','ready').select('id');if(claimed.error)throw claimed.error;if(!claimed.data?.length)continue;
  const items=reminder.payload.items as {invoice_id:string;label:string;amount_cents:number;paid_cents:number}[];
  const text=`EDUCAR\nOutstanding: ARS ${(reminder.payload.total_cents/100).toFixed(2)}\n${items.map(i=>`${i.label}: ARS ${((i.amount_cents-i.paid_cents)/100).toFixed(2)} (invoice ${i.invoice_id})`).join('\n')}`;
  // shortcut: attach an itemized invoice CSV; replace with institutional PDF invoices before production acceptance.
  const invoice=items.map(i=>[i.invoice_id,JSON.stringify(i.label),i.amount_cents,i.paid_cents].join(',')).join('\n');
  try {
   const response=await fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:`Bearer ${apiKey}`,'Content-Type':'application/json','Idempotency-Key':`billing/${reminder.id}`},body:JSON.stringify({from:sender,to:[reminder.recipient],subject:reminder.kind==='debt'?'EDUCAR · Outstanding balance':'EDUCAR · Monthly invoice',text,attachments:reminder.kind==='month_end'?[{filename:`invoices-${date}.csv`,content:btoa(unescape(encodeURIComponent('invoice_id,concept,amount_cents,paid_cents\n'+invoice)))}]:[]}),signal:AbortSignal.timeout(15000)});
   if(!response.ok){await client.from('billing_reminders').update({status:'failed'}).eq('id',reminder.id);continue;}
   const result=await response.json();const updated=await client.from('billing_reminders').update({status:'sent',provider_id:result.id}).eq('id',reminder.id);if(updated.error)throw updated.error;sent++;
  } catch { /* A sending row is intentionally retained for manual reconciliation after an ambiguous provider outcome. */ }
 }
 return Response.json({prepared:prepared.data,sent});
 }catch{return Response.json({error:'Reminder processing failed; inspect server configuration and queue.'},{status:500});}
});
