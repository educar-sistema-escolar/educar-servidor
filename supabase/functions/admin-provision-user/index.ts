import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const allowedRoles = new Set(['superadmin', 'teacher', 'parent', 'student']);

type ProvisionPayload = {
  email?: unknown;
  full_name?: unknown;
  role?: unknown;
};

function response(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function fail(message: string, status: number) {
  return response({ error: message }, status);
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return fail('Method not allowed', 405);

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const authorization = request.headers.get('Authorization');

  if (!supabaseUrl || !serviceRoleKey || !anonKey || !authorization) {
    return fail('Server configuration or authorization is incomplete.', 500);
  }

  const token = authorization.replace(/^Bearer\s+/i, '');
  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const adminClient = createClient(supabaseUrl, serviceRoleKey);

  const { data: callerData, error: callerError } = await callerClient.auth.getUser();
  if (callerError || !callerData.user) return fail('Authenticated user required.', 401);

  const { data: callerProfile, error: profileError } = await adminClient
    .from('profiles')
    .select('role,is_active')
    .eq('id', callerData.user.id)
    .maybeSingle();

  if (
    profileError ||
    callerProfile?.role !== 'superadmin' ||
    callerProfile.is_active !== true
  ) {
    return fail('Active superadmin role required.', 403);
  }

  let payload: ProvisionPayload;
  try {
    payload = await request.json();
  } catch {
    return fail('Request body must be valid JSON.', 400);
  }

  const email = typeof payload.email === 'string' ? payload.email.trim().toLowerCase() : '';
  const fullName = typeof payload.full_name === 'string' ? payload.full_name.trim() : '';
  const role = typeof payload.role === 'string' ? payload.role : '';

  if (!/^\S+@\S+\.\S+$/.test(email)) return fail('A valid email is required.', 400);
  if (fullName.length < 2 || fullName.length > 160) return fail('A valid full name is required.', 400);
  if (!allowedRoles.has(role)) return fail('Requested role is not allowed.', 400);

  const { data: existingProfile } = await adminClient
    .from('profiles')
    .select('id')
    .eq('email', email)
    .maybeSingle();
  if (existingProfile) return fail('An account with that email already exists.', 409);

  // Invitation onboarding keeps credentials out of the administration UI and avoids a shared temporary password.
  const { data: invitation, error: invitationError } = await adminClient.auth.admin.inviteUserByEmail(
    email,
    { data: { full_name: fullName } },
  );

  if (invitationError || !invitation.user) {
    return fail(invitationError?.message || 'Unable to invite the user.', 400);
  }

  const { data: profile, error: updateError } = await adminClient
    .from('profiles')
    .update({ email, full_name: fullName, role, is_active: true })
    .eq('id', invitation.user.id)
    .select('id,email,full_name,role,is_active,created_at')
    .single();

  if (updateError || !profile) {
    // Auth and public.profile are separate resources, so delete the invited user when profile setup fails.
    await adminClient.auth.admin.deleteUser(invitation.user.id);
    return fail('The user invitation could not be completed.', 500);
  }

  return response({ account: profile, invited: true }, 201);
});
