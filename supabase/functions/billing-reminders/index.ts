import { PDFDocument, StandardFonts } from 'npm:pdf-lib@1.17.1';
import { createClient } from 'npm:@supabase/supabase-js@2.116.0';
const required = (key: string) => { const value = Deno.env.get(key); if (!value)
    throw new Error(`Missing server configuration: ${key}`); return value; };
Deno.serve(async (request) => {
    if (request.method !== 'POST')
        return new Response('Method not allowed', { status: 405 });
    const secret = Deno.env.get('BILLING_CRON_SECRET');
    if (!secret || request.headers.get('Authorization') !== `Bearer ${secret}`)
        return new Response('Unauthorized', { status: 401 });
    try {
        const client = createClient(required('SUPABASE_URL'), required('SUPABASE_SERVICE_ROLE_KEY'));
        let input: { dry_run?: boolean } = {};
        const body = await request.text();
        if (body) { try { input=JSON.parse(body); } catch { return Response.json({error:'Invalid JSON body'},{status:400}); } }
        const dryRun = input.dry_run === true;
        const apiKey = dryRun ? '' : required('RESEND_API_KEY');
        const sender = dryRun ? '' : required('BILLING_FROM_EMAIL');
        const date = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Argentina/Buenos_Aires', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
        let preparedCount = 0;
        for (let days = dryRun ? -1 : 6; days >= 0; days--) {
            const day = new Date(`${date}T12:00:00Z`);
            day.setUTCDate(day.getUTCDate() - days);
            const prepared = await client.rpc('prepare_billing_reminders', { p_date: day.toISOString().slice(0, 10) });
            if (prepared.error)
                throw prepared.error;
            preparedCount += prepared.data ?? 0;
        }
        const { data: queue, error } = await client.from('billing_reminders').select('*').eq('status', 'ready').lte('reminder_date', date).order('reminder_date').limit(50);
        if (error)
            throw error;
        let sent = 0;
        const previews: unknown[] = [];
        let queueFailure = false;
        for (const reminder of queue ?? []) {
            if (!dryRun) {
                const claimed = await client.from('billing_reminders').update({ status: 'sending', attempts: (reminder.attempts ?? 0)+1, last_attempt_at: new Date().toISOString(), last_error: null }).eq('id', reminder.id).eq('status', 'ready').select('id');
                if (claimed.error) throw claimed.error;
                if (!claimed.data?.length) continue;
            }
            const fresh = await client.rpc('refresh_billing_reminder', {p_reminder:reminder.id});
            if (fresh.error) {
                if (!dryRun) {const reset=await client.from('billing_reminders').update({status:'ready',last_error:'context_refresh_failed'}).eq('id',reminder.id);if(reset.error)queueFailure=true;}
                continue;
            }
            if (!fresh.data) {
                if (!dryRun) {const skipped=await client.from('billing_reminders').update({status:'failed',last_error:'no_eligible_recipient_or_debt'}).eq('id',reminder.id);if(skipped.error)queueFailure=true;}
                continue;
            }
            reminder.payload=fresh.data.payload;
            reminder.recipient=fresh.data.recipient;
            const items = reminder.payload.items as {
                invoice_id: string;
                student_name: string;
                period: string;
                due_date: string;
                label: string;
                amount_cents: number;
                paid_cents: number;
            }[];
            const visibleItems = reminder.kind === 'debt' ? items.filter(i => i.amount_cents > i.paid_cents) : items;
            const text = `Hola ${reminder.payload.name ?? ''}:\n\n${reminder.kind === 'debt' ? 'Te recordamos los importes pendientes:' : 'Te enviamos el detalle del período y los estados de cuenta adjuntos:'}\n\n${visibleItems.map(i => `${i.student_name} · período ${i.period} · vencimiento ${i.due_date}\n${i.label}: ARS ${(i.amount_cents / 100).toFixed(2)} · pendiente ARS ${((i.amount_cents - i.paid_cents) / 100).toFixed(2)}`).join('\n\n')}\n\nTotal pendiente: ARS ${(reminder.payload.total_cents / 100).toFixed(2)}\n\nLas transferencias quedan sujetas a verificación de la institución.\nEducar para Transformar`;
            const attachments = [];
            try {
                if (reminder.kind === 'month_end')
                    for (const invoiceId of [...new Set(items.map(i => i.invoice_id))]) {
                        const pdf = await PDFDocument.create();
                        const font = await pdf.embedFont(StandardFonts.Helvetica);
                        let page = pdf.addPage([595, 842]);
                        let y = 790;
                        const line = (value: string) => { if (y < 50) {
                            page = pdf.addPage([595, 842]);
                            y = 790;
                        } page.drawText(value.normalize('NFKD').replace(/[^\x20-\x7E]/g, '').slice(0, 95), { x: 40, y, size: 11, font }); y -= 22; };
                        line('EDUCAR - Estado de cuenta');
                        line(`Factura ${invoiceId}`);
                        line(`Estado emitido ${date}`);
                        line('Las transferencias requieren verificacion de la escuela.');
                        const rows = items.filter(i => i.invoice_id === invoiceId);
                        line(`Alumno: ${rows[0]?.student_name ?? 'Unknown'}`);
                        line(`Periodo: ${rows[0]?.period ?? 'Unknown'}`);
                        line(`Vencimiento: ${rows[0]?.due_date ?? 'Unknown'}`);
                        for (const item of rows) {
                            line(`${item.label}: ARS ${(item.amount_cents / 100).toFixed(2)} / pagado ${(item.paid_cents / 100).toFixed(2)}`);
                        }
                        line(`Saldo pendiente ARS ${(rows.reduce((sum, i) => sum + i.amount_cents - i.paid_cents, 0) / 100).toFixed(2)}`);
                        attachments.push({ filename: `invoice-${invoiceId}.pdf`, content: await pdf.saveAsBase64() });
                    }
            }
            catch {
                if (!dryRun) { const reset = await client.from('billing_reminders').update({ status: 'ready', last_error:'pdf_generation_failed' }).eq('id', reminder.id);
                if (reset.error) queueFailure = true; }
                continue;
            }
            if (dryRun) { previews.push({id:reminder.id,kind:reminder.kind,text,attachments});continue; }
            try {
                const response = await fetch('https://api.resend.com/emails', { method: 'POST', headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json', 'Idempotency-Key': `billing/${reminder.id}` }, body: JSON.stringify({ from: sender, to: [reminder.recipient], subject: reminder.kind === 'debt' ? 'Educar · Recordatorio de saldo pendiente' : 'Educar · Estado de cuenta mensual', text, attachments }), signal: AbortSignal.timeout(15000) });
                if (!response.ok) {
                    const status = response.status === 429 ? 'ready' : response.status >= 500 || response.status === 408 ? 'sending' : 'failed';
                    const rejected = await client.from('billing_reminders').update({ status, last_error:`provider_http_${response.status}` }).eq('id', reminder.id);
                    if (rejected.error) queueFailure = true;
                    continue;
                }
                const result = await response.json();
                if (typeof result.id !== 'string' || !result.id) throw new Error('Missing provider receipt');
                const updated = await client.from('billing_reminders').update({ status: 'sent', provider_id: result.id }).eq('id', reminder.id);
                if (updated.error) { queueFailure = true; throw updated.error; }
                sent++;
            }
            catch {
                // An ambiguous provider outcome must never be replayed automatically.
                const held=await client.from('billing_reminders').update({last_error:'provider_outcome_ambiguous'}).eq('id',reminder.id);
                if(held.error)queueFailure=true;
            }
        }
        if (queueFailure) throw new Error('Queue state could not be persisted.');
        return Response.json(dryRun ? {dry_run:true,prepared:0,sent:0,previews} : { prepared: preparedCount, sent });
    }
    catch {
        return Response.json({ error: 'Reminder processing failed; inspect server configuration and queue.' }, { status: 500 });
    }
});
