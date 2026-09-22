import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const allowedRoles = new Set(['superadmin', 'teacher', 'parent', 'guardian', 'student']);

type ProvisionPayload = {
  email?: unknown;
  full_name?: unknown;
  role?: unknown;
};

type Profile = {
  id: string;
  email: string;
  full_name: string;
  role: string;
  is_active: boolean;
  account_status: 'invited' | 'active' | 'inactive';
  invited_at: string | null;
  activated_at: string | null;
  created_at: string;
};

type LinkedIdentity = {
  person_id: string;
  person_created: boolean;
  student_id: string | null;
  student_created: boolean;
  teacher_id: string | null;
  teacher_created: boolean;
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

function isPlainPayload(value: unknown): value is ProvisionPayload {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  return Object.keys(value).every((key) => ['email', 'full_name', 'role'].includes(key));
}

function hasValidName(value: string) {
  return value.length >= 2
    && value.length <= 160
    && !/[\u0000-\u001f\u007f]/.test(value)
    && value.split(/\s+/).filter(Boolean).length >= 2;
}

function safeProvisionError(status: number) {
  return fail(
    status === 409
      ? 'An account with that email or role already exists.'
      : 'The user invitation could not be completed.',
    status,
  );
}

async function compensateNewIdentity(
  adminClient: ReturnType<typeof createClient>,
  linkedIdentity: LinkedIdentity | null,
  authUserId: string,
) {
  if (linkedIdentity?.student_created && linkedIdentity.student_id) {
    await adminClient.from('students').delete().eq('id', linkedIdentity.student_id);
  }
  if (linkedIdentity?.teacher_created && linkedIdentity.teacher_id) {
    await adminClient.from('teachers').delete().eq('id', linkedIdentity.teacher_id);
  }
  if (linkedIdentity?.person_created) {
    await adminClient.from('people').delete().eq('id', linkedIdentity.person_id);
  }
  await adminClient.auth.admin.deleteUser(authUserId);
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return fail('Method not allowed', 405);

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const authorization = request.headers.get('Authorization');

  if (!supabaseUrl || !serviceRoleKey || !anonKey) {
    return fail('Server configuration or authorization is incomplete.', 500);
  }
  if (!/^Bearer\s+\S+$/i.test(authorization ?? '')) return fail('Authenticated user required.', 401);

  const token = authorization!.replace(/^Bearer\s+/i, '');
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

  if (profileError || callerProfile?.role !== 'superadmin' || callerProfile.is_active !== true) {
    return fail('Active superadmin role required.', 403);
  }

  let rawPayload: unknown;
  try {
    rawPayload = await request.json();
  } catch {
    return fail('Request body must be valid JSON.', 400);
  }

  if (!isPlainPayload(rawPayload)) return fail('Request body contains unsupported fields.', 400);

  const email = typeof rawPayload.email === 'string' ? rawPayload.email.trim().toLowerCase() : '';
  const fullName = typeof rawPayload.full_name === 'string'
    ? rawPayload.full_name.trim().replace(/\s+/g, ' ')
    : '';
  const role = typeof rawPayload.role === 'string' ? rawPayload.role : '';

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 320) {
    return fail('A valid email is required.', 400);
  }
  if (!hasValidName(fullName)) return fail('A valid full name is required.', 400);
  if (!allowedRoles.has(role)) return fail('Requested role is not allowed.', 400);

  const { data: profiles, error: existingProfileError } = await adminClient
    .from('profiles')
    .select('id,email,full_name,role,is_active,account_status,invited_at,activated_at,created_at')
    .limit(1000);

  if (existingProfileError) return safeProvisionError(500);
  const existingProfile = (profiles ?? []).find(
    (profile) => typeof profile.email === 'string' && profile.email.trim().toLowerCase() === email,
  );

  if (existingProfile) {
    if (!existingProfile.is_active || existingProfile.role !== role) return safeProvisionError(409);

    const { error: linkError } = await callerClient.rpc('link_provisioned_identity', {
      p_profile_id: existingProfile.id,
      p_email: email,
      p_full_name: fullName,
      p_role: role,
    });

    if (linkError) return safeProvisionError(linkError.code === '23505' ? 409 : 500);

    const { data: account, error: refreshedProfileError } = await adminClient
      .from('profiles')
      .select('id,email,full_name,role,is_active,account_status,invited_at,activated_at,created_at')
      .eq('id', existingProfile.id)
      .single();

    if (refreshedProfileError || !account) return safeProvisionError(500);
    return response({ account: account as Profile, invited: false, idempotent: true }, 200);
  }

  const applicationOrigin = request.headers.get('origin')?.replace(/\/$/, '')
    || Deno.env.get('APP_URL')?.replace(/\/$/, '');
  const { data: invitation, error: invitationError } = await adminClient.auth.admin.inviteUserByEmail(
    email,
    {
      data: { full_name: fullName },
      ...(applicationOrigin ? { redirectTo: `${applicationOrigin}/login?mode=reset` } : {}),
    },
  );

  if (invitationError || !invitation.user) return safeProvisionError(400);

  const { data: linkedIdentity, error: linkError } = await callerClient.rpc('link_provisioned_identity', {
    p_profile_id: invitation.user.id,
    p_email: email,
    p_full_name: fullName,
    p_role: role,
  });

  if (linkError) {
    await adminClient.auth.admin.deleteUser(invitation.user.id);
    return safeProvisionError(linkError.code === '23505' ? 409 : 500);
  }

  const invitedAt = new Date().toISOString();
  const isActivated = Boolean(invitation.user.email_confirmed_at);
  const { data: account, error: accountError } = await adminClient
    .from('profiles')
    .update({
      account_status: isActivated ? 'active' : 'invited',
      invited_at: invitedAt,
      activated_at: isActivated ? invitedAt : null,
    })
    .eq('id', invitation.user.id)
    .select('id,email,full_name,role,is_active,account_status,invited_at,activated_at,created_at')
    .single();

  if (accountError || !account) {
    await compensateNewIdentity(adminClient, linkedIdentity as LinkedIdentity | null, invitation.user.id);
    return safeProvisionError(500);
  }

  return response({ account: account as Profile, invited: true, idempotent: false }, 201);
});
