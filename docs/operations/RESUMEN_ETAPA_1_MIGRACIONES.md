# RESUMEN ETAPA 1 — Migraciones y pruebas reales del backend

**Fecha:** 26/10/2026.
**Proyecto:** `nhwsgmijdsxzuxgpllhy` — CentroEducativo / mmoschen's Project / main.
**Resultado:** ETAPA 1 completada. Las tres migraciones solicitadas están aplicadas y sus operaciones fueron probadas en Supabase real. Fue necesaria una cuarta corrección mínima del trigger de aprobación.
**Autorización:** aplicación directa sobre datos DEMO ficticios, sin respaldo previo, expresamente autorizada por el usuario. No se generaron backups ni infraestructura adicional.

## 1. Migraciones aplicadas y resultado

| Versión | Archivo | Resultado remoto |
|---|---|---|
| `20261025120000` | `fix_enrollment_approval_and_dining_usage.sql` | Aplicada: aprobación sin ambigüedad y trigger inválido de comedor retirado |
| `20261026030000` | `fix_demo_schedule_overlaps.sql` | Aplicada: horarios DEMO corregidos y restricciones docentes operativas |
| `20261026120000` | `fix_guardian_link_ambiguity.sql` | Aplicada: RPC de vínculos familiares operativa |
| `20261026133000` | `fix_approval_guardian_trigger_ambiguity.sql` | Corrección adicional aplicada: desbloquea el trigger que asocia al responsable de una solicitud aprobada |

Se usó el SQL Editor autenticado del proyecto indicado. Las primeras tres correcciones se ejecutaron en orden dentro de una transacción y se registraron con su SQL en `supabase_migrations.schema_migrations`. La corrección adicional se ejecutó en otra transacción con su propio registro.

El historial tenía únicamente `20260911210000` y `20260921150000`; ahora conserva esas dos versiones más las cuatro de esta etapa. No se marcaron versiones históricas como aplicadas ni se ejecutaron archivos anteriores automáticamente. No se usaron `db push`, `db reset`, recreaciones de tablas ni eliminaciones masivas.

Una consulta independiente confirmó que las cuatro fuentes SQL registradas coinciden con los archivos del repositorio. Para comparar sus MD5 se normalizaron los finales de línea: el editor conserva CRLF. Se verificaron además las definiciones reales de funciones y la presencia/ausencia de los triggers correspondientes, después de confirmar las transacciones.

## 2. Correcciones realizadas

- Aprobación: variable `resolved_person_id` para evitar confusión con `students.person_id`.
- Comedor: eliminación de `dining_usage_set_updated_at`; la tabla no tiene esa columna y su upsert solo debe cambiar `used`.
- Horarios: cambio del bloque académico DEMO Primario del lunes a 09:00–10:00; distribución de los tres niveles deportivos en 16:00–17:00, 17:00–18:00 y 18:00–19:00. Se conservaron asignaciones y filas válidas; no se borraron horarios ni profesores.
- Vínculos de tutores: variable `resolved_guardian_person_id` en `link_student_guardian`.
- Trigger de aprobación: misma corrección de nombre en `link_approved_enrollment_guardian_for_request`, preservando la asociación por DNI, sus permisos y la lógica de tutor principal.

No se cambió el diseño ni el código del frontend durante esta etapa. No se modificaron contraseñas ni cuentas existentes, no se crearon cuentas nuevas y no se desactivó RLS. No se recargó el conjunto DEMO.

## 3. Pruebas ejecutadas y resultados

| Verificación | Resultado |
|---|---|
| Preflight remoto | Proyecto correcto, dependencias existentes, historial revisado; 1 cruce académico y 12 cruces deportivos antes del cambio |
| Aprobación vía Supabase Auth + RPC real | Solicitud DEMO aprobada y persistida; alumno y matrícula correctos |
| Repetición de aprobación | Mismos IDs; una persona, un alumno y una matrícula activa |
| Rechazo controlado | Cambió estado y motivo; repetición idempotente; no creó alumno; reversión con ROLLBACK |
| Aprobar una solicitud ya rechazada | Rechazado con check_violation |
| Uso de comedor vía RPC real | Inserción con used=true y actualización a false sobre el mismo ID; una sola fila |
| Cruces remotos después del cambio | **0 académicos, 0 deportivos** |
| Superposición académica intencional | Rechazada con SQLSTATE 23P01 |
| Reasignación docente incompatible | Rechazada con SQLSTATE 23P01 |
| Horario adyacente | Aceptado |
| Superposición deportiva intencional | Rechazada con SQLSTATE 23P01 |
| Nuevo vínculo tutor–alumno | Creado mediante RPC y repetido sin duplicados dentro de una transacción; revertido con ROLLBACK |
| Vínculo familiar ya existente por API | RPC ejecutada y repetida con el mismo ID |
| RLS de familia por sesión Auth real | Solo dos hijos; alumno recién aprobado oculto; tres RPC administrativas rechazadas con 42501 |
| Postflight de catálogo | Cuatro correcciones aplicadas; RLS activa en las seis tablas verificadas; fixture temporal otra vez pendiente |
| Backend `node --test tests/*.test.mjs` | **17/17 aprobadas**; se amplió la suite PostgreSQL existente para incluir el trigger real de asociación de responsable |
| Frontend `npm test` | **14/14 aprobadas** |
| `node --check scripts/verify-stage1-live.mjs` | Aprobado |
| `git diff --check` en ambos repositorios | Aprobado; advertencia LF/CRLF preexistente de RegistrationPage.tsx |

El rechazo, la reprobación del estado rechazado, los intentos de superposición, la reasignación y el tercer vínculo temporal se probaron en el proyecto real con `ROLLBACK`. Luego se consultó de nuevo la base para confirmar que esas pruebas no dejaron cambios.

La suite local reutiliza la infraestructura temporal ya existente; no se configuró una plataforma de pruebas nueva. Las comprobaciones remotas anteriores son evidencia adicional independiente de esos fixtures locales.

## 4. Estado de aprobación de alumnos

Solicitud persistida: `5d04739e-13a2-4f36-acf5-f536abc093d3`, **Aprobada Demo**, DNI ficticio `47100002`, ciclo 2027.

- Estado final: `approved`.
- Alumno creado: `57d5155a-b1dd-4c18-b71a-0ac95fbbfa04`.
- Matrícula creada: `5f87d9d3-b68a-444b-a099-e78475c7d512`.
- Curso: `DEMO-27-PRI-A`, DEMO 4to Grado A, ciclo 2027.
- Una persona por DNI, un alumno y una matrícula activa. La repetición no creó registros adicionales.
- El trigger creó el vínculo del responsable por DNI sin dar de alta una cuenta Auth.
- Alumnos totales: 15 antes, **16 después**; el incremento corresponde al alumno aprobado.

Estado final de las tres solicitudes existentes: **1 pendiente, 1 aprobada y 1 rechazada**. `Pendiente Demo` (`43965105-2910-4f36-b37c-8625d5c6624f`) se usó para el rechazo controlado y volvió a `pending` tras el rollback. La solicitud rechazada anterior se conservó.

## 5. Estado del comedor

La RPC `record_dining_usage` insertó y actualizó el uso de Emilia Fernandez (`DEMO-2027-A005`) en su matrícula de comedor `e1f7becc-e8b4-4619-8f48-186a3d8c434b` para `2027-04-01`.

Se comprobó `true → false`, mismo ID y **una sola fila** para inscripción/fecha. El resultado persistido es `used=false`. No reapareció el error de `updated_at`.

También se guardó un uso desde el formulario existente del frontend, que mostró **“Uso de comedor registrado.”** usando `record_dining_usage`. Esa prueba de interfaz utilizó la fecha predeterminada `2026-10-26` y el alumno ficticio Emilia; no se atribuye esa escritura a la fecha 2027 de la prueba API. El formulario se probó dos veces sobre la misma inscripción/fecha, sin error de trigger.

## 6. Estado de horarios

Los conflictos pasaron de **1 a 0** en horarios académicos y de **12 a 0** entre grupos deportivos. Permanecen ocho horarios académicos activos del ciclo DEMO 2027.

La agenda real del docente en el frontend muestra el lunes:

- 08:00–09:00: Matematicas, DEMO Sala de 5 A.
- 09:00–10:00: Matematicas, DEMO 4to Grado A.

Las pruebas remotas confirmaron rechazo de superposición entre cursos, entre grupos deportivos y por reasignación docente incompatible. Un bloque adyacente fue aceptado. Los intentos controlados fueron revertidos; se conservaron las asignaciones originales.

El alcance de esta migración es la validación dentro de horarios académicos y dentro de grupos deportivos. No se amplió en esta etapa a un motor único de conflictos entre todos los tipos de servicio.

## 7. Estado de asociación familiar

La familia `familia.demo.2027@educar.example` conserva exactamente:

- Emilia Fernandez, `DEMO-2027-A005`.
- Joaquin Ledesma, `DEMO-2027-A010`.

`link_student_guardian` funciona con sesión superadmin: se repitió el vínculo existente y devolvió el mismo ID. Se creó además un vínculo nuevo con `DEMO-2027-A006` dentro de la prueba SQL y se revirtió; no quedó un tercer hijo asociado.

La sesión parent real ve dos alumnos y dos vínculos; el alumno recién aprobado no es visible para esa familia. Intentos parent de aprobar solicitudes, registrar uso de comedor o vincular un alumno fueron rechazados con **42501**. La UI familiar recargada conservó los dos hijos. Se volvió a ejecutar la verificación de materias y servicios familiares: 2 matrículas de curso, 6 de materias, 3 deportivas, 2 de transporte y 2 de comedor.

## 8. Error encontrado y solución

La primera aprobación después de las tres migraciones falló con **42702: guardian_person_id ambiguo**. La causa era una cuarta función: `link_approved_enrollment_guardian_for_request`, ejecutada por el trigger posterior al cambio de estado de una solicitud. La migración de `link_student_guardian` no cubría esa función distinta.

La operación fallida se revirtió automáticamente; no quedó un alumno parcial. Se inspeccionó la definición remota, se preparó y probó la migración `20261026133000_fix_approval_guardian_trigger_ambiguity.sql`, y luego se aplicó. La aprobación completa, su repetición y la creación de responsable/vínculo pasaron tras la corrección.

El test PostgreSQL anterior no instalaba ese trigger; se amplió para ejecutarlo de verdad y comprobar una única asociación por DNI, incluida una segunda ejecución del helper. No se forzó el guardado desactivando triggers ni RLS.

## 9. Pendientes reales

**No quedan bloqueos abiertos de las operaciones obligatorias de ETAPA 1.**

El historial de migraciones previo continúa incompleto por decisión deliberada: solo se registró lo aplicado y comprobado en esta etapa. Una reconstrucción completa futura del historial requiere comparar objetos; no se hizo ni es necesaria para ejecutar estas correcciones.

Siguen fuera de esta etapa los filtros/exportaciones de reportes ya documentados, QA integral de accesibilidad y la publicación de una presentación protegida. No se realizó una auditoría general ni se modificó el diseño para abordarlos.

## 10. Archivos modificados y Git

Archivos nuevos de esta etapa en backend:

- `supabase/migrations/20261026133000_fix_approval_guardian_trigger_ambiguity.sql`.
- `scripts/verify-stage1-live.mjs`: por defecto solo lectura; `--write-demo` ejecuta únicamente la aprobación, comedor y repetición de vínculo sobre fixtures fijos, validando proyecto y perfil activo.
- `tests/stage1-live-acceptance.sql`: rechazo, estados, horarios, reasignación y vínculo nuevo con ROLLBACK.
- `tests/stage1-postflight.sql`: comprobación de catálogo, RLS e invariantes finales.
- `docs/operations/RESUMEN_ETAPA_1_MIGRACIONES.md`: copia versionable de este cierre.

Se ampliaron `tests/pending-rpcs-fixture.sql` y `tests/pg-schedule-regressions.test.mjs` para cubrir el trigger real de aprobación. Se actualizó el aviso de estado de `docs/operations/demo-unblock-20261026.md`; su procedimiento anterior de backup queda como referencia histórica, superado para esta ejecución por la autorización expresa del usuario.

En el directorio padre se crearon este resumen y la actualización de `INFORME_CAMBIOS_Y_PENDIENTES.md`. El directorio padre no es la raíz de ninguno de los dos repositorios; la copia en `backend/docs/operations` permite incluir el cierre en un futuro commit de backend.

Ambos repositorios continúan en `codex/final-presentation-qa`. El frontend conserva exactamente sus cambios previos; esta etapa no añadió cambios de código o diseño allí. El backend conserva los cambios previos más los listados arriba. No se ejecutaron `git add`, commit, push ni despliegues a Vercel. Las evidencias de ejecución están en `backend/tmp`, ignorado por Git; no contienen contraseñas en los informes públicos.

### Repetir verificaciones sin volver a aplicar migraciones

Desde `backend`:

```powershell
node scripts/verify-stage1-live.mjs
node scripts/provision-demo-family.mjs
node --test tests/*.test.mjs
```

En el SQL Editor del mismo proyecto ejecutar `tests/stage1-postflight.sql`. Para repetir los casos controlados usar `tests/stage1-live-acceptance.sql`, que termina en ROLLBACK y exige el fixture Pendiente Demo todavía pendiente. No volver a ejecutar las migraciones como mecanismo de prueba.
