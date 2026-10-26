# Bloqueos DEMO — procedimiento y estado comprobado

> **Estado superado por ETAPA 1 (26/10/2026):** las tres migraciones y una corrección adicional ya están aplicadas y probadas. El usuario autorizó ejecutarlas sin backups en este entorno académico. No se generaron backups. Consultar [RESUMEN_ETAPA_1_MIGRACIONES.md](RESUMEN_ETAPA_1_MIGRACIONES.md). Las instrucciones y bloqueos de las secciones siguientes se conservan como referencia del estado anterior; no representan pendientes actuales.

Proyecto: `nhwsgmijdsxzuxgpllhy`, organización CentroEducativo, `mmoschen's Project`, rama remota `main` identificada como Production. Fecha: 26/10/2026.

## Función: causa y despliegue realizado

El dashboard tenía una función con nombre visible `admin-provision-user`, pero slug real `quick-worker`. El nombre visible no cambia la URL. La llamada del frontend (`functions.invoke('admin-provision-user')`) era correcta para el repositorio y recibía `404 NOT_FOUND` porque ese slug no estaba desplegado.

Se desplegó el contenido de `supabase/functions/admin-provision-user/index.ts` mediante el editor autenticado del dashboard **con slug `admin-provision-user`**. Se conservó `quick-worker` para no eliminar una función existente. La configuración de JWT legacy se sincronizó con `supabase/config.toml`: `verify_jwt=false`; la función valida la sesión en Auth con `getUser()` y exige perfil superadmin activo antes de acceder al cliente servidor. CORS declara POST y OPTIONS. Se probaron OPTIONS 200, POST sin sesión 401, parent/teacher/student 403 y superadmin con cuenta DEMO existente 200.

Los secretos `SUPABASE_URL`, `SUPABASE_ANON_KEY` y `SUPABASE_SERVICE_ROLE_KEY` los aporta Supabase al runtime. No se copiaron al frontend ni se crearon claves nuevas. Referencia oficial: [secretos de Edge Functions](https://supabase.com/docs/guides/functions/secrets), [configuración por función](https://supabase.com/docs/guides/functions/function-configuration).

Para futuros despliegues desde este repositorio, con sesión CLI autorizada:

```powershell
Set-Location 'C:\Users\juanm\OneDrive - Facultad Regional Resistencia\METODOLOGIA DE SISTEMA II\backend'
npx supabase login
npx supabase projects list
npx supabase functions list --project-ref nhwsgmijdsxzuxgpllhy
npx supabase functions deploy admin-provision-user --project-ref nhwsgmijdsxzuxgpllhy
```

El último comando despliega solo esa función, no aplica migraciones. Confirmar slug y configuración en el dashboard después de ejecutarlo.

## Familia creada y comprobada

`familia.demo.2027@educar.example` tiene Auth confirmado, perfil activo `parent` y `app_metadata.demo_cycle=2027`. Contraseña aleatoria guardada solo en `tmp/family-credentials.local` y `frontend/.env.local`, ambos ignorados. No se envió correo a un buzón ficticio.

Hijos: `DEMO-2027-A005` (Emilia Fernandez) y `DEMO-2027-A010` (Joaquin Ledesma), ya existentes, sin perfil Auth asociado y con matrícula activa 2027. No se crearon ni modificaron alumnos reales. Se guardó una instantánea local de perfiles, personas y vínculos antes de la operación aditiva; **no es un backup completo de base de datos**.

El script de provisión valida proyecto, perfil administrador, identidades ficticias y ciclo antes de escribir. Usa Auth Admin para la creación, el endpoint canónico para vincular la identidad existente y el cliente servidor para estos dos vínculos DEMO. Esto último fue necesario porque la RPC remota `link_student_guardian` falla con SQLSTATE 42702: `guardian_person_id` ambiguo en ON CONFLICT. La corrección está en `20261026120000_fix_guardian_link_ambiguity.sql`, aún sin aplicar. El formulario administrativo general para crear vínculos sigue pendiente de esa migración.

```powershell
# Solo lectura; usa las credenciales DEMO locales, no imprime contraseñas.
node scripts/provision-demo-family.mjs
node scripts/verify-demo-access.mjs

# Solo para volver a completar la misma identidad DEMO; no resetea contraseñas.
# Requiere SUPABASE_SERVICE_ROLE_KEY en el entorno del proceso servidor.
node scripts/provision-demo-family.mjs --apply

# Habilita la tarjeta local únicamente después de las verificaciones de API.
# Antes de usarlo en otro entorno comprobar también la selección de hijos en UI.
node scripts/provision-demo-family.mjs --enable-footer
```

Se comprobó login, exactamente dos alumnos y dos vínculos visibles, 2 matrículas de curso, 6 de materias, 3 de deportes, 2 de transporte y 2 de comedor. Una consulta explícita a otro alumno devuelve cero filas; las RPC administrativas se rechazan con 42501. El portal permite seleccionar ambos hijos y muestra sus cursos/horarios/servicios. No tienen notas cargadas; no se inventaron notas.

## Migraciones: no aplicadas

La consulta de preflight al catálogo remoto confirmó:

| Control | Resultado |
|---|---|
| `supabase_migrations.schema_migrations` | Solo `20260911210000`, `20260921150000` |
| Aprobación usa `resolved_person_id` | false |
| Trigger inválido `dining_usage_set_updated_at` existe | true |
| Validación docente nueva existe | false |
| RPC tutor usa variable no ambigua | false |
| Backups programados | Plan Free: no incluidos |

Hay objetos posteriores presentes sin el historial CLI correspondiente. **No ejecutar `db push`, `db reset` ni marcar todo el historial como aplicado.** No se obtuvo contraseña/conexión PostgreSQL para `pg_dump`; el login al dashboard no concede automáticamente esa credencial. La clave de servicio REST tampoco sirve como contraseña PostgreSQL.

Pendientes exactos, en orden:

1. `20261025120000_fix_enrollment_approval_and_dining_usage.sql`
2. `20261026030000_fix_demo_schedule_overlaps.sql`
3. `20261026120000_fix_guardian_link_ambiguity.sql`

### Respaldo y aplicación, después de obtener conexión PostgreSQL autorizada

Obtener la conexión directa o pooler de sesión desde **Connect** del proyecto; copiar host, puerto y usuario a variables `PGHOST`, `PGPORT`, `PGUSER`, `PGDATABASE=postgres`, `PGSSLMODE=require`. No incluir contraseñas en argumentos ni historial. `pg_dump -W` y `psql -W` las solicitan de forma interactiva. Confirmar que el host/usuario corresponda a este ref; no usar una conexión de otro proyecto.

```powershell
New-Item -ItemType Directory -Force -Path .\tmp | Out-Null
$backupFile = Join-Path (Resolve-Path .\tmp) ('educar-before-migrations-' + (Get-Date -Format yyyyMMdd-HHmmss) + '.dump')
pg_dump -W --format=custom --no-owner --no-acl --file=$backupFile
if ($LASTEXITCODE -ne 0) { throw 'Fallo pg_dump: no aplicar migraciones' }
pg_restore --list $backupFile | Set-Content ($backupFile + '.list')
if ($LASTEXITCODE -ne 0) { throw 'Backup ilegible: no aplicar migraciones' }
Get-FileHash -Algorithm SHA256 $backupFile
psql -X -W -v ON_ERROR_STOP=1 -c 'select version,name from supabase_migrations.schema_migrations order by version;'
```

El dump contiene esquema y datos de los esquemas no internos, incluido Auth si el usuario conectado tiene permiso. Revisar su lista y confirmar `auth.users`, `auth.identities`, `public.*`, políticas, funciones y `supabase_migrations.schema_migrations`. Conservar aparte el código Edge del repositorio y la configuración de plataforma; un dump no copia archivos de Storage ni secretos del runtime.

**Antes de tocar la instancia**, restaurar el dump en un proyecto Supabase desechable compatible y comprobar identidades, vínculos, tablas y políticas. Usar un servicio libpq separado configurado localmente para ese clon, por ejemplo `educar_restore_check`, para no reutilizar la conexión institucional accidentalmente:

```powershell
# Solo sobre el clon vacío. Nunca agregar --clean contra la instancia institucional.
pg_restore -W --dbname='service=educar_restore_check' --no-owner --no-acl --exit-on-error $backupFile
```

No considerar `pg_restore --list` una prueba de restauración. Si los objetos administrados de Auth/Storage necesitan un procedimiento específico del proveedor, detener la aplicación hasta verificarlo en el clon.

Después del respaldo restaurable y la revisión del historial, ejecutar **cada** migración solo si su versión aún no figura, inspeccionar antes las filas DEMO afectadas por la segunda y confirmar que las definiciones base coinciden con el repositorio. Estos comandos aplican únicamente los tres arreglos revisados y registran cada versión en la misma transacción; no reconstruyen el historial antiguo:

```powershell
$pending = @(
  @{ version='20261025120000'; name='fix_enrollment_approval_and_dining_usage' },
  @{ version='20261026030000'; name='fix_demo_schedule_overlaps' },
  @{ version='20261026120000'; name='fix_guardian_link_ambiguity' }
)
foreach ($migration in $pending) {
  $file = '.\supabase\migrations\' + $migration.version + '_' + $migration.name + '.sql'
  $record = "insert into supabase_migrations.schema_migrations(version,name) values ('$($migration.version)','$($migration.name)');"
  psql -X -W -v ON_ERROR_STOP=1 --single-transaction -f $file -c $record
  if ($LASTEXITCODE -ne 0) { throw ('Fallo ' + $migration.version + ': detener y revisar') }
}
```

Probar primero en el clon las operaciones de `tests/database-regressions-acceptance.sql` (termina en ROLLBACK) con fixtures de dos solicitudes pendientes y un comedor activo. Ese archivo selecciona solicitudes existentes: **no ejecutarlo contra la institución sin adaptarlo a IDs DEMO explícitos**. Para la instancia real usar casos DEMO identificados y respaldados: aprobación/repetición de la misma solicitud, rechazo de otra, alta y actualización del mismo uso de comedor, horarios solapados rechazados, adyacentes aceptados, reasignación docente rechazada y vínculo tutor repetido sin duplicados. Verificar los cambios desde la UI y volver a ejecutar ambos scripts de acceso. Nada de esto se marcó como aprobado remotamente en esta entrega.

## Validación local y límites

`node --test tests/*.test.mjs`: 17 pruebas aprobadas. PostgreSQL temporal ejecuta las tres migraciones correctivas: aprobación/repetición, comedor true→false, horarios/reasignación y vínculo de tutor/idempotencia/permisos. No sustituye las políticas y triggers completos de la instancia Supabase remota. Los tests financieros usan fixtures compatibles con plataforma y verifican RLS real local.

Los doce reportes respondieron a 72 consultas (sin filtros, por año, nivel, deporte, recorrido y combinación). Es una prueba de respuesta, no una garantía de que todos los filtros se apliquen a todos los reportes: `student_overview` no cambia y los filtros ajenos al tipo se ignoran. Permanece pendiente mostrar en UI solo los filtros compatibles o ampliar sus implementaciones SQL, además de verificar todas las exportaciones.
