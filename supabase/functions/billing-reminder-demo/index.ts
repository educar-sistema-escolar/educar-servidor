import { createClient } from 'npm:@supabase/supabase-js@2.116.0';

const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const reply = (body: unknown, status = 200) => Response.json(body, { status, headers: cors });

Deno.serve(async request => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (request.method !== 'POST') return reply({ error: 'Método no permitido.' }, 405);
  const url = Deno.env.get('SUPABASE_URL');
  const anon = Deno.env.get('SUPABASE_ANON_KEY');
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const secret = Deno.env.get('BILLING_CRON_SECRET');
  const auth = request.headers.get('Authorization');
  if (!url || !anon || !service || !secret || Deno.env.get('BILLING_DELIVERY_MODE') !== 'demo') return reply({ error: 'La demostración no está configurada.' }, 503);
  if (!/^Bearer\s+\S+$/i.test(auth ?? '')) return reply({ error: 'Iniciá sesión como administrador.' }, 401);
  const caller = createClient(url, anon, { global: { headers: { Authorization: auth! } } });
  const { data: user, error: authError } = await caller.auth.getUser();
  if (authError || !user.user) return reply({ error: 'Sesión inválida.' }, 401);
  let input: unknown;
  try { input = await request.json(); } catch { return reply({ error: 'Solicitud inválida.' }, 400); }
  if (!input || typeof input !== 'object' || Array.isArray(input) || Object.keys(input).some(k => k !== 'kind') || !['debt', 'month_end'].includes((input as { kind: string }).kind)) return reply({ error: 'Tipo de recordatorio inválido.' }, 400);
  const { data: runId, error: createError } = await caller.rpc('create_billing_demo_run', { p_kind: (input as { kind: string }).kind });
  if (createError) return reply({ error: createError.code === '42501' ? 'Acceso exclusivo para administración.' : createError.message }, createError.code === '42501' ? 403 : 429);
  const admin = createClient(url, service);
  try {
    await fetch(`${url}/functions/v1/billing-reminders`, { method: 'POST', headers: { Authorization: `Bearer ${anon}`, 'x-billing-secret': secret, 'Content-Type': 'application/json' }, body: JSON.stringify({ demo_run_id: runId }), signal: AbortSignal.timeout(45000) });
  } catch { /* The queue record preserves an ambiguous outcome for inspection. */ }
  const { data: run, error: readError } = await admin.from('billing_demo_runs').select('id,kind,status,recipient,created_at,last_attempt_at,last_error').eq('id', runId).single();
  if (readError || !run) return reply({ error: 'No se pudo consultar el resultado; no repitas sin revisar.' }, 503);
  return reply(run);
});
