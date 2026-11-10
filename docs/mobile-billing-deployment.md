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

Function `billing-reminders` authenticates POST calls with a dedicated high-entropy `BILLING_CRON_SECRET` in `x-billing-secret`, in addition to the gateway JWT check. The handler's explicit secret check remains mandatory.

Server-only configuration:

- `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` supplied to the deployed function.
- `RESEND_API_KEY` for a verified sender account.
- `BILLING_FROM_EMAIL` using a provider-verified sender domain.
- `BILLING_CRON_SECRET`, generated securely and stored in the scheduler secret store.

For real-family delivery, obtain explicit operational approval and complete the tests and sender setup first. Configure a trusted recurring POST scheduler (e.g. Supabase Cron using Vault-protected secrets) every 10 minutes. Do not paste secrets into committed SQL, logs or issue comments. Maintain the Buenos Aires institutional holiday calendar. The worker prepares the previous seven calendar dates and drains at most 50 ready rows per invocation, including backlog; repeated scheduling drains larger batches.

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

## Actualización 3 de noviembre de 2026: worker con auditoría y modo de prueba

La migración local `20261103191021_billing_reminder_delivery_audit.sql` agrega contador, fecha y error del último intento a la cola existente. La función de servidor vuelve a consultar vínculos activos y saldos aprobados antes del envío; una deuda saldada o una relación revocada se excluye. El cambio requiere migración y worker de la misma versión. No se aplicó al proyecto remoto ni se desplegó el worker.

Enviar al endpoint una solicitud autenticada con `BILLING_CRON_SECRET` y cuerpo `{"dry_run":true}` devuelve previsualizaciones y PDF en base64 de filas ya existentes en estado `ready`, sin enviar correos ni modificar cola. Solo usar en entorno aislado con datos DEMO: la respuesta contiene información de facturación. El modo prueba no crea filas; para probar la preparación usar la función SQL en una transacción reversible en una base aislada. Si no hay proveedor real configurado el modo normal falla sin marcar entregas como enviadas. El modo prueba fue verificado con dobles de red y PDF, no en Deno desplegado.

Cada intento registra categoría de error sin datos sensibles. Una respuesta ambigua queda en `sending` para reconciliación manual. El control de idempotencia no elimina la posibilidad de que un pago se apruebe después de la última lectura y antes de la aceptación del correo: el mensaje refleja el saldo consultado antes del envío. Se debe mantener el calendario de feriados institucional, que estaba vacío en la consulta remota del 03/11/2026. La consulta de `pg_extension` confirmó que `pg_cron` no estaba instalado en ese momento; verificar también cualquier programador externo antes de activarlo.

PostgreSQL 18 local con fixtures de compatibilidad pasó pruebas de saldos, RLS, duplicados, bloqueo concurrente, feriado, idempotencia, exclusión de deuda saldada y revocación. No equivale a probar Supabase Storage ni correo real.

## Configuración DEMO del 9 de noviembre de 2026

La función `billing-reminders` se desplegó mediante el editor de Supabase con JWT legado del gateway activado y un secreto independiente en la cabecera `x-billing-secret`. Cron usa Vault para obtener ambos valores. El remitente de pruebas es `onboarding@resend.dev`; la cuenta de Resend limita este remitente al buzón verificado. La clave tiene permiso de envío. No guardar claves en Git ni en este documento.

La configuración remota usa `BILLING_DELIVERY_MODE=demo`, `BILLING_DEMO_GUARDIAN_ID` para un tutor ficticio específico, `BILLING_DEMO_RECIPIENT` para el buzón verificado y `BILLING_SEND_ENABLED=true`. En modo DEMO, el worker filtra la cola por ese identificador y comprueba que el destinatario revalidado coincida con el buzón configurado. Si faltan los valores o el interruptor no es exactamente `true`, no envía. `live` permite salir de esta restricción y **no debe establecerse sin aprobación expresa** y sin un dominio verificado, calendario y pruebas operativas. Las claves JWT heredadas serán retiradas por Supabase; hay que migrar la autenticación del gateway antes de su retirada.

Se cargó un fixture sin inicio de sesión, con tutor/alumno y factura ficticios; su usuario Auth permanece bloqueado. Enviados manualmente desde `pg_net` dos registros de prueba con fechas del 20 y del último día hábil de octubre: ambos llegaron al buzón verificado y la cola registró `sent`, un intento e identificador de proveedor. El correo de deuda mostró cuota pendiente $750 y comedor $500; el mensual adjuntó un PDF legible con esos conceptos y saldo de $1.250. El PDF se titula estado de cuenta y contiene identificador de factura; no es una factura fiscal certificada ni se validó que reemplace una factura institucional formal. Los registros se insertaron para probar la entrega: no demuestran por sí solos que un cron ejecutado en los días reales genere los mensajes correctos. El calendario remoto de feriados estaba vacío; cargar y mantener feriados antes de cualquier uso general.

La migración `20261103191021` se ejecutó manualmente en el editor SQL remoto y **no quedó registrada en el historial de migraciones**. Sus adiciones de columnas se hicieron idempotentes localmente; reconciliar el historial con el CLI antes de aplicar el conjunto de migraciones. No volver a ejecutar a ciegas la versión anterior. El programador debe supervisarse mediante `cron.job_run_details` y `net._http_response`; reconciliar manualmente cualquier fila `sending` antes de reintentarse.

Se instaló `pg_cron` y `pg_net`, con el trabajo `educar-billing-reminders` cada diez minutos. Para verificarlo se redujo temporalmente a un minuto: Cron informó `succeeded` y la respuesta HTTP fue `200` con `sent: 0` después de las dos entregas, sin repetirlas; se restableció el intervalo de diez minutos. La preparación actual consulta todas las familias aun en modo DEMO, aunque el procesamiento y envío quedan restringidos al tutor ficticio. No habilitar modo general sin revisar y reconciliar previamente cualquier fila `ready` de la cola. Un trabajo SQL exitoso solo prueba el encolado HTTP: revisar también su respuesta.

## Acciones de demostración del panel — 10 de noviembre de 2026

El panel local de Facturación llama a `billing-reminder-demo` con la sesión del administrador. El servidor valida la sesión y la RPC comprueba `is_billing_admin`; una cuenta familiar recibió 403 en la prueba real. La RPC utiliza exclusivamente los recordatorios enviados del tutor ficticio fijo y crea una ejecución separada en `billing_demo_runs`. El worker reutiliza la revalidación, generación de PDF y envío existentes, restringidos por los secretos DEMO y por los identificadores del alumno y factura ficticios. No cambia los registros de la cola automática ni las facturas. Hay un intervalo mínimo de 60 segundos, un máximo de 12 pruebas en 24 horas y bloqueo ante ejecuciones `ready` o `sending` pendientes de revisión. Los resultados ambiguos deben reconciliarse con Resend antes de cualquier intervención manual.

Ambos botones se probaron en el navegador con la web local conectada a Supabase: el correo de deuda y el cierre llegaron al buzón verificado, y el PDF recibido mostró cuota $1.000 ($250 pagados), comedor $500 y saldo $1.250. Una segunda pulsación inmediata fue rechazada por el intervalo de seguridad. El PDF sigue siendo un estado de cuenta, no una factura fiscal certificada. El remitente de pruebas Resend no permite usar destinatarios generales.

La migración `20261109230000_billing_demo_runs.sql` también fue aplicada manualmente desde el editor y debe reconciliarse con el historial de migraciones antes de futuros despliegues por CLI; el archivo local admite repetición. El panel modificado está en el repositorio local; no se publicó la web. Las dos funciones remotas fueron desplegadas para la prueba y la verificación JWT legada quedó activada; migrar esta dependencia antes del retiro de claves heredadas.
