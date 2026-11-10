# educar-server

Supabase-first repository for database migrations and server-side project documentation.

## Structure

- `supabase/migrations/`: versioned PostgreSQL migrations.
- `docs/`: architecture, database, and operational documentation.
- `tests/`: server-side verification tests.

No custom Node API is included until a concrete backend requirement exists.

## Envío de estado de cuenta de prueba

La función `family-statement-test` permite a una cuenta familiar activa enviar por Resend un PDF informativo con hasta 12 facturas de un alumno al que tiene acceso. Valida la sesión mediante Supabase Auth, consulta los datos con la autorización del usuario y limita tanto la cuenta como el destinatario al correo configurado en `BILLING_DEMO_RECIPIENT`. El PDF no es una factura fiscal. Esta función no procesa la cola de `billing-reminders`.

Para habilitar el envío hay que desplegar la función y configurar en el servidor `BILLING_DEMO_RECIPIENT`, `BILLING_FROM_EMAIL` y `RESEND_API_KEY`, además de las variables de Supabase disponibles para la función. El remitente debe estar habilitado en Resend. No publicar claves en el cliente ni en el repositorio. Desplegada el 10/11/2026: solicitud autenticada de la familia DEMO con HTTP 200 y `sent: true`; aceptación por Resend confirmada. La recepción en la bandeja debe confirmarse.

Pruebas locales con proveedor y base simulados: `node --test tests/family-statement-test.test.mjs`.

La cuenta de prueba se limita con `BILLING_TEST_ACCOUNT_EMAIL` (por defecto `familia.demo.2027@educar.example`). Se respetan `BILLING_DELIVERY_MODE=demo` y `BILLING_SEND_ENABLED=true`. El destinatario permanece en `BILLING_DEMO_RECIPIENT`.
