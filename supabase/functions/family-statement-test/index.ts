import { createClient } from 'npm:@supabase/supabase-js@2.116.0';
import { PDFDocument, StandardFonts } from 'npm:pdf-lib@1.17.1';

const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const reply = (body: unknown, status = 200) => Response.json(body, { status, headers: cors });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
  if (req.method !== 'POST') return reply({ error: 'Método no permitido.' }, 405);
  try {
    const url = Deno.env.get('SUPABASE_URL');
    const key = Deno.env.get('SUPABASE_ANON_KEY');
    const testEmail = Deno.env.get('BILLING_DEMO_RECIPIENT')?.trim().toLowerCase();
    const sender = Deno.env.get('BILLING_FROM_EMAIL');
    const resendKey = Deno.env.get('RESEND_API_KEY');
    const authorization = req.headers.get('Authorization');
    if (!url || !key || !testEmail || !sender || !resendKey || Deno.env.get('BILLING_DELIVERY_MODE') !== 'demo' || Deno.env.get('BILLING_SEND_ENABLED') !== 'true') return reply({ error: 'El envío de prueba no está configurado.' }, 503);
    if (!authorization?.startsWith('Bearer ')) return reply({ error: 'Iniciá sesión nuevamente.' }, 401);
    const client = createClient(url, key, { global: { headers: { Authorization: authorization } } });
    const { data: auth, error: authError } = await client.auth.getUser();
    if (authError || !auth.user || auth.user.email?.toLowerCase() !== (Deno.env.get('BILLING_TEST_ACCOUNT_EMAIL') ?? 'familia.demo.2027@educar.example')) return reply({ error: 'El envío está habilitado solo para la cuenta de prueba.' }, 403);
    const { data: profile, error: profileError } = await client.from('profiles').select('role,is_active,account_status').eq('id', auth.user.id).maybeSingle();
    if (profileError || !profile?.is_active || profile.account_status !== 'active' || !['parent', 'guardian'].includes(profile.role)) return reply({ error: 'Se requiere una cuenta familiar activa.' }, 403);
    const { childId } = await req.json();
    if (typeof childId !== 'string' || !/^[0-9a-f-]{36}$/i.test(childId)) return reply({ error: 'Seleccioná un alumno.' }, 400);
    const { data: child, error: childError } = await client.from('students').select('id,people(first_name,last_name)').eq('id', childId).eq('is_active', true).maybeSingle();
    if (childError || !child) return reply({ error: 'No se encontró un alumno vinculado.' }, 403);
    const { data: invoices, error: invoiceError } = await client.from('invoices').select('period,due_date,invoice_items(label,amount_cents,paid_cents)').eq('student_id', childId).order('period', { ascending: false }).limit(12);
    if (invoiceError) throw invoiceError;
    if (!invoices?.length) return reply({ error: 'No hay facturas para el alumno seleccionado.' }, 404);
    const pdf = await PDFDocument.create();
    const font = await pdf.embedFont(StandardFonts.Helvetica);
    let page = pdf.addPage([595, 842]);
    let y = 790;
    const line = (text: string) => { if (y < 50) { page = pdf.addPage([595, 842]); y = 790; } page.drawText(text.normalize('NFKD').replace(/[^\x20-\x7e]/g, '').slice(0, 95), { x: 40, y, size: 11, font }); y -= 20; };
    line('EDUCAR - Estado de cuenta de prueba');
    line('Documento informativo, no es factura fiscal.');
    const person = Array.isArray(child.people) ? child.people[0] : child.people;
    line(`Alumno: ${person?.first_name ?? ''} ${person?.last_name ?? ''}`);
    let total = 0;
    for (const invoice of invoices) {
      line(`Periodo: ${invoice.period} - Vencimiento: ${invoice.due_date}`);
      for (const item of invoice.invoice_items ?? []) {
        const balance = item.amount_cents - item.paid_cents;
        total += balance;
        line(`${item.label}: ARS ${(item.amount_cents / 100).toFixed(2)} - pendiente ${(balance / 100).toFixed(2)}`);
      }
    }
    line(`Saldo pendiente total: ARS ${(total / 100).toFixed(2)}`);
    const sent = await fetch('https://api.resend.com/emails', { method: 'POST', headers: { Authorization: `Bearer ${resendKey}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ from: sender, to: [testEmail], subject: 'Educar · Estado de cuenta de prueba', text: 'Adjuntamos el estado de cuenta de prueba del alumno seleccionado.', attachments: [{ filename: 'estado-de-cuenta.pdf', content: await pdf.saveAsBase64() }] }), signal: AbortSignal.timeout(15000) });
    if (!sent.ok) return reply({ error: 'El proveedor no aceptó el correo de prueba.' }, 502);
    return reply({ sent: true });
  } catch { return reply({ error: 'No se pudo completar el envío. Si hubo una demora, verificá la bandeja antes de reintentar.' }, 500); }
});
