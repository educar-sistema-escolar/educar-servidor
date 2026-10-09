# Billing deployment and verification

## Do not deploy blindly

The October 8 iteration adds local source only. No production database migration, function, mail delivery or scheduler was executed. Run the complete migration chain and pgTAP suites in a disposable Supabase environment first. This repository's local `supabase/config.toml` is a placeholder plus the narrow email-function setting, not a fully initialized local stack.

## Database

Apply the `20261008*` migrations in timestamp order after all existing identity/service migrations. Run `supabase test db` only against a configured local environment. Required behaviors include foreign-child denial, inactive-parent denial, cross-invoice item denial, pending-not-paid semantics, duplicate idempotency, atomic partial approval, private receipts and holiday-aware reminders. Tests are under `supabase/tests/mobile_billing*.test.sql`; their presence is not execution evidence.

Use a billing administrator to configure effective prices, maintain `billing_non_business_days`, and issue monthly invoices. Active service enrollments must have prices; invoice issuance rejects unpriced services. The active transport route at issuance is snapshotted, so service changes do not modify prior invoices.

## Mobile and web

Only public Supabase URL/public key belong in the clients. Never copy service-role credentials into `EXPO_PUBLIC_*` or `VITE_*`. Add `educar://recovery` (or the explicitly chosen HTTPS recovery URL) to the Supabase Auth redirect allowlist. Recovery email templates must use the confirmation URL, not a hardcoded unrelated site URL. Verify the native scheme in a development/EAS build.

The mobile client is family-only; administrative billing appears at `/privado/facturacion` in the existing web portal. Confirm the institution's administrative role mapping before production acceptance.

## Scheduled mail

Function `billing-reminders` authenticates POST calls with a dedicated high-entropy `BILLING_CRON_SECRET`. Only this function has `verify_jwt = false`, because a scheduler bearer secret is not a Supabase user JWT. The handler's explicit secret check remains mandatory.

Server-only configuration:

- `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` supplied to the deployed function.
- `RESEND_API_KEY` for a verified sender account.
- `BILLING_FROM_EMAIL` using a provider-verified sender domain.
- `BILLING_CRON_SECRET`, generated securely and stored in the scheduler secret store.

Deploy only after explicit operational approval and successful disposable tests. Configure a trusted recurring POST scheduler (e.g. Supabase Cron using Vault-protected secrets) every 10 minutes. Do not paste secrets into committed SQL, logs or issue comments. Maintain the Buenos Aires institutional holiday calendar. The worker prepares the previous seven business-calendar dates and drains at most 50 ready rows per invocation, including backlog; repeated scheduling drains larger batches.

Queue outcomes:

- `ready`: not sent; next invocation may claim it.
- `sending`: claimed, or provider result ambiguous. Reconcile manually against the provider's idempotency key `billing/<reminder id>` before any replay. Do not reset automatically after timeouts.
- `sent`: provider accepted and provider ID persisted.
- `failed`: explicit provider rejection; diagnose configuration/data before a controlled retry.

Provider idempotency is a second safety layer, not a substitute for the durable queue. The provider's retention window is finite; never blindly replay ambiguous older messages. Outages longer than seven days require explicit `prepare_billing_reminders(date)` backfill under the server service role. Do not email families for test scenarios in production.

Monthly emails attach per-invoice PDFs containing student, period, due date, full invoice concepts, paid amounts and outstanding balance. The document is an institutional statement, not a certified fiscal invoice. Business receipt requirements need institutional acceptance.

## Storage maintenance

Receipts are private PDFs/JPGs/PNGs, at most 5 MB. Signed URLs expire after 60 seconds. Billing administrators may inspect only associated files. The global SECURITY DEFINER unattached check prevents inactive/unlinked parents from deleting retained payment evidence. Orphan uploads may be cleaned only after confirming no committed submission references them; ambiguous operations require reconciliation first.

## Verification evidence

`node --test tests/billing-reminders.test.mjs` exercises the actual transpiled worker with mock network/database/PDF boundaries: auth denial, 51-row repeated drainage, PDF failure requeue and ambiguous-provider hold. It needs the sibling mobile TypeScript dev dependency. It does not send mail or prove PostgreSQL policies.

Docker daemon was unavailable during the iteration; the attempted `supabase test db` did not pass. Deno/native deployment and live provider integration were not executed. Do not mark these requirements production-complete from unit tests alone.

## Primary references

- [Supabase Auth redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls)
- [Resend idempotency keys](https://resend.com/docs/dashboard/emails/idempotency-keys)
- [Expo SDK57 navigation migration](https://docs.expo.dev/router/migrate/sdk-55-to-56/)
