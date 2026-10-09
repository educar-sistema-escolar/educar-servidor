import { PDFDocument, StandardFonts } from 'npm:pdf-lib@1.17.1';
import { createClient } from 'npm:@supabase/supabase-js@2.116.0';
const required=(key:string)=>{const value=Deno.env.get(key);if(!value)throw new Error(`Missing server configuration: ${key}`);return value;};
Deno.serve(async(request)=>{
 if(request.method!=='POST')return new Response('Method not allowed',{status:405});
 const secret=Deno.env.get('BILLING_CRON_SECRET');if(!secret||request.headers.get('Authorization')!==`Bearer ${secret}`)return new Response('Unauthorized',{status:401});
 try {
 const client=createClient(required('SUPABASE_URL'),required('SUPABASE_SERVICE_ROLE_KEY'));const apiKey=required('RESEND_API_KEY');const sender=required('BILLING_FROM_EMAIL');
 const date=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Argentina/Buenos_Aires',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 let preparedCount=0;for(let days=6;days>=0;days--){const day=new Date(`${date}T12:00:00Z`);day.setUTCDate(day.getUTCDate()-days);const prepared=await client.rpc('prepare_billing_reminders',{p_date:day.toISOString().slice(0,10)});if(prepared.error)throw prepared.error;preparedCount+=prepared.data??0;}
 const {data:queue,error}=await client.from('billing_reminders').select('*').eq('status','ready').lte('reminder_date',date).order('reminder_date').limit(50);if(error)throw error;
 let sent=0;
 for(const reminder of queue??[]){
  const claimed=await client.from('billing_reminders').update({status:'sending'}).eq('id',reminder.id).eq('status','ready').select('id');if(claimed.error)throw claimed.error;if(!claimed.data?.length)continue;
  const items=reminder.payload.items as {invoice_id:string;student_name:string;period:string;due_date:string;label:string;amount_cents:number;paid_cents:number}[];
  const text=`EDUCAR\nOutstanding: ARS ${(reminder.payload.total_cents/100).toFixed(2)}\n${items.map(i=>`${i.label}: ARS ${((i.amount_cents-i.paid_cents)/100).toFixed(2)} (invoice ${i.invoice_id})`).join('\n')}`;
  const attachments=[];
  try {
  if(reminder.kind==='month_end')for(const invoiceId of [...new Set(items.map(i=>i.invoice_id))]){
   const pdf=await PDFDocument.create();const font=await pdf.embedFont(StandardFonts.Helvetica);let page=pdf.addPage([595,842]);let y=790;
   const line=(value:string)=>{if(y<50){page=pdf.addPage([595,842]);y=790;}page.drawText(value.normalize('NFKD').replace(/[^\x20-\x7E]/g,'').slice(0,95),{x:40,y,size:11,font});y-=22;};
   line('EDUCAR - Invoice');line(`Invoice ${invoiceId}`);line(`Issued account statement ${date}`);line('Transfer payments require school verification.');
   const rows=items.filter(i=>i.invoice_id===invoiceId);for(const item of rows){line(`${item.label}: ARS ${(item.amount_cents/100).toFixed(2)} / paid ${(item.paid_cents/100).toFixed(2)}`);}
   line(`Outstanding ARS ${(rows.reduce((sum,i)=>sum+i.amount_cents-i.paid_cents,0)/100).toFixed(2)}`);
   attachments.push({filename:`invoice-${invoiceId}.pdf`,content:await pdf.saveAsBase64()});
  }
  } catch {await client.from('billing_reminders').update({status:'ready'}).eq('id',reminder.id);continue;}
  try {
   const response=await fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:`Bearer ${apiKey}`,'Content-Type':'application/json','Idempotency-Key':`billing/${reminder.id}`},body:JSON.stringify({from:sender,to:[reminder.recipient],subject:reminder.kind==='debt'?'EDUCAR · Outstanding balance':'EDUCAR · Monthly invoice',text,attachments}),signal:AbortSignal.timeout(15000)});
   if(!response.ok){await client.from('billing_reminders').update({status:'failed'}).eq('id',reminder.id);continue;}
   const result=await response.json();const updated=await client.from('billing_reminders').update({status:'sent',provider_id:result.id}).eq('id',reminder.id);if(updated.error)throw updated.error;sent++;
  } catch { /* A sending row is intentionally retained for manual reconciliation after an ambiguous provider outcome. */ }
 }
 return Response.json({prepared:preparedCount,sent});
 }catch{return Response.json({error:'Reminder processing failed; inspect server configuration and queue.'},{status:500});}
});
