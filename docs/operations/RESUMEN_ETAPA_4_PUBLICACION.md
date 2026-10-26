# ETAPA 4 — DEMO final y pruebas; publicación pospuesta

Fecha: 26/10/2026, America/Buenos_Aires.

**Estado:** demo cargada y comprobada en Supabase CentroEducativo, con frontend funcionando en `http://127.0.0.1:5175/`. **Sin commit, push ni despliegue**, según la instrucción posterior del usuario: trabajar en Supabase y localhost y esperar su indicación para publicar. Este informe no acredita una publicación en Internet.

Proyecto utilizado exclusivamente: `nhwsgmijdsxzuxgpllhy`, **mmoschen's Project / CentroEducativo / main**. Se leyeron los tres cierres anteriores y se conservaron sus cambios. No se volvió a ejecutar el seed institucional ni la cadena histórica de migraciones.

## 1. Datos DEMO agregados

`backend/scripts/stage4-demo.sql` agrega datos; no modifica identidades, contraseñas, matrículas ni servicios existentes. Se ejecutó dos veces en el proyecto real: ambas terminaron con 4 publicaciones, 3 respuestas y 4 facturas. Usa UUID fijos para publicaciones/respuestas, restricciones de unicidad para votos/precios y búsqueda alumno/período antes de emitir por RPC. Conserva precios existentes ante conflictos.

Foro: bienvenida al ciclo, repaso de Matemática, cuidado de la escuela y encuentro deportivo. Autores autenticados institucionales asociados a `DEMO-2027-A001`, `A002` y `A003`. Se agregaron tres votos de discusión y uno de respuesta; después se agregó un voto desde la UI. El autor lo fija el trigger desde Auth, sin suplantar cuentas ni desactivar RLS. El nombre público actual de estos perfiles es el fallback **“Estudiante”**; se preservó ese snapshot y su `author_id`. Las fechas de publicación son las fechas reales de carga, 26/10/2026; los temas tratan sobre 2027.

Precios ficticios vigentes desde 01/01/2027, expresados internamente en centavos:

| Concepto | Importe ARS | Configuraciones |
|---|---:|---:|
| Cuota | 65.000 | 1 |
| Actividad deportiva | 12.000 | 12 grupos existentes |
| Transporte | 28.000 | 4 recorridos existentes |
| Comedor | 35.000 | 2 servicios existentes |

Facturas emitidas por `issue_monthly_invoice`, con ítems derivados de las inscripciones reales DEMO de 2027:

| Alumno | Período | ID de factura | Total ARS | Estado final |
|---|---|---|---:|---|
| Emilia Fernandez / A005 | Marzo 2027 | `249617d2-e177-4e14-b462-18b6a23ae4f0` | 140.000 | Pagada |
| Emilia Fernandez / A005 | Abril 2027 | `b40bc6cf-31a6-4eb3-9c06-f07554b4cdad` | 140.000 | Pendiente; transferencia en revisión |
| Joaquin Ledesma / A010 | Marzo 2027 | `47fb7d99-2502-4d66-9781-6663edeec9a3` | 152.000 | Pendiente |
| Joaquin Ledesma / A010 | Abril 2027 | `376da2cc-76de-46d4-8aa4-295173c6fbe5` | 152.000 | Pendiente |

Total ficticio: ARS 584.000; pagado ARS 140.000; pendiente ARS 444.000. Ambos alumnos conservan su responsable familiar existente. No se enviaron cobros, correos de recordatorio ni cargos; no se conectó una pasarela.

## 2. Foro: resultado real

En navegador integrado: login alumno, listado de los cuatro temas, búsqueda “Matemática” con un resultado, categoría Deportes con su tema, combinación incompatible con estado vacío, vuelta a Todas, apertura de discusión, respuesta existente, fecha y votos. El voto desde UI cambió de 1 a 2 y quedó seleccionado. Se conservan los permisos de alumnos; no se añadieron accesos para familias o docentes.

El contenido DEMO no se simula en React: procede de las tablas del proyecto. La carga repetida no duplicó temas, respuestas ni votos de la carga original.

## 3. Facturación y Storage binario

`backend/scripts/verify-stage4-storage.mjs` usa las credenciales locales existentes mediante Supabase Auth, la API real Storage y las RPC reales. No usa service role. Se ejecutó con éxito en dos pasadas completas, conservando los mismos IDs y estados.

| Referencia ficticia | Transferencia | Estado |
|---|---|---|
| DEMO-2027-PAGO-MARZO | `2e4ea5e4-d2c9-4201-981d-08d652ab52f8` | approved |
| DEMO-2027-REVISION-ABRIL | `a8f033fd-bba6-4d87-a4db-b97bfbb09dda` | pending |

Se generaron PDF válidos de 697 y 701 bytes, con “DEMO 2027 - SIN VALOR FISCAL” y “No acredita un pago real”. La familia subió los binarios a su carpeta de `transfer-receipts`, presentó cada transferencia mediante `submit_transfer` y repitió la presentación con idéntico resultado. Administración aprobó únicamente el ejemplo de marzo mediante `review_transfer`. La transferencia pendiente no imputó pagos.

Se verificó asociación de comprobante, transferencia, factura y responsable. Familia y administración generaron URL firmadas de 60 segundos y descargaron exactamente los bytes originales. El alumno ajeno recibió HTTP 400 al intentar leer el objeto privado o generar una URL; el acceso público también fue rechazado. El bucket sigue privado y RLS permanece activa.

**Límite del mecanismo:** una URL firmada es un enlace portador; quien recibe ese enlace puede usarlo hasta su vencimiento. No se afirma que esté ligado a la sesión del destinatario. No se guardaron enlaces firmados ni tokens en este informe.

La interfaz administrativa abrió el PDF de abril con su botón existente y el visor lo mostró correctamente. No se creó una pantalla web familiar de pagos. Los dos PDF asociados se conservan como evidencia útil; un tercer PDF temporal sin asociación se subió, eliminó por la política autorizada y se comprobó inaccesible después.

El reporte administrativo marzo–abril mostró una factura completa y tres incompletas. Los ingresos se filtran por fecha real de aprobación, que en esta carga es octubre de 2026; las facturas se filtran por su período de 2027. Por eso el ingreso ficticio aparece en el reporte de octubre y no en el rango marzo–abril de 2027.

## 4. Formularios y limpieza

| Área | Evidencia ejecutada |
|---|---|
| Solicitud pública | Sin sesión: campos obligatorios rechazados; formulario de cuatro pasos completado; rechazo sin confirmar datos; envío real y número `EPT-2026-104498`. Se eliminó después. El formulario público utiliza el año actual 2026; esta prueba descartable no se presenta como matrícula DEMO 2027. |
| Registro de cuenta | Se conserva el flujo institucional: no hay autoalta ni almacenamiento local de contraseñas. Las cuentas permanentes existentes se verificaron con Auth. |
| Docentes | UI: vacío rechazado; alta `QA4-UI-TEMP`; edición de especialidad; desactivación confirmada. SQL real con ROLLBACK: alta/edición, DNI duplicado, payload inválido y denegación sin permisos. |
| Niveles | UI: obligatorios rechazados y alta temporal confirmada en listado. SQL con ROLLBACK: alta, edición, desactivación y código duplicado. |
| Cursos | UI: relación con nivel temporal, capacidad negativa rechazada y alta válida para 2027. SQL con ROLLBACK: alta, edición, desactivación, duplicado y capacidad negativa. |
| Materias | UI: alta confirmada y código duplicado rechazado con mensaje comprensible. SQL con ROLLBACK: alta, edición, desactivación y duplicado. |
| Solicitud/RPC pública | SQL bajo rol anon: alta válida, duplicado, DNI inválido y correo inválido; todo revertido. |
| Asociación e invitación | Cuatro identidades existentes y asociación familiar con exactamente dos hijos comprobadas. Tests de provisión validan preflight, autorización y rechazo de entradas inválidas sin invitar. No se creó una cuenta Auth adicional ni se certificó recepción de una nueva invitación por correo. |

Pruebas SQL reproducibles: `backend/tests/stage4-masterdata.sql`. Limpieza delimitada: `backend/tests/stage4-cleanup.sql`. Los fixtures de UI se eliminaron por sus códigos, DNI, correo y nombres de prueba, con transacción y FK activas. No se eliminó ningún alumno, docente ni maestro institucional DEMO.

Postflight final: **16 alumnos, 6 docentes, 3 solicitudes originales, 3 niveles, 6 cursos, 4 materias; cero fixtures temporales**. Permanecen 4 temas, 3 respuestas, 19 precios, 4 facturas, 2 transferencias y 2 objetos/comprobantes asociados. Bucket privado, RLS activa y dos hijos de la familia confirmados por consulta independiente. Consultas repetibles: `backend/tests/stage4-postflight.sql`.

## 5. Visual, accesibilidad y responsive

Se conservó el diseño institucional azul. Cambios puntuales de esta etapa:

- Foro: tonos de votos, metadatos y controles secundarios más oscuros para mejorar contraste; sin cambiar estructura.
- Facturación: ausencias se muestran como “—”; fecha inicial del reporte separada del período de emisión. UI confirmó reporte 2027 y emisión aún en su valor inicial 2026, sin alterar uno al editar el otro.
- Solicitud pública: se reemplazaron los main interiores por section; se comprobó un único landmark main.

Se capturaron alumno, familia, docente y administración/facturación a anchos CSS efectivos de **390, 768 y 1440 px**, además del detalle del foro. Las mediciones válidas tienen `scrollWidth == clientWidth`; las tablas se desplazan dentro de su contenedor. Se conservan también intentos intermedios con otros anchos en el JSON; no se confunden con las mediciones requeridas.

Menú móvil administrativo: Shift+Tab desde Cerrar menú llega a Cerrar sesión dentro del diálogo; Tab vuelve a Cerrar menú; Escape cierra y devuelve foco al disparador. Modal académico: `aria-modal=true`, `aria-labelledby` apunta a un título existente; Escape devuelve foco a Nuevo. Se comprobaron estados Guardando/Enviando/Validando y mensajes de error.

Las observaciones axe de Etapa 3 se abordaron con revisión manual focalizada de contraste, nombres/referencias ARIA y teclado. **No se ejecutó una nueva pasada completa de axe ni lector de pantalla**, ni se afirma certificación WCAG o cero incomplete en todas las pantallas.

## 6. Validación técnica definitiva

| Validación | Resultado |
|---|---|
| Frontend `npm run lint` | PASS, sin errores |
| Frontend `npm run build` | PASS, TypeScript y Vite |
| Frontend `npm test` | 18/18 PASS |
| Control build público | 69 archivos JS/HTML/map; 8 valores DEMO configurados ausentes; ninguna clave de servidor detectada |
| Backend `node --test tests/*.test.mjs` | 17/17 PASS, incluidos PostgreSQL, RLS, pagos parciales, concurrencia, horarios y vínculos |
| SQL remoto | Carga repetida, aceptación de maestros con ROLLBACK, limpieza y postflight: PASS |
| Storage/API real | Dos pasadas completas PASS; mismos IDs, permisos y bytes verificados |
| CSV real | `students_by_course`, ciclo 2027: 15 filas y 5 columnas, descargado y parseado |
| `git diff --check` | PASS en ambos repositorios; avisos de normalización LF/CRLF |
| Candidatos Git | Sin contraseñas DEMO configuradas, claves privadas, claves de servidor o archivos env reales detectados |

OneDrive bloqueó inicialmente lecturas de Git y dependencias; Vite devolvió UNKNOWN/read y TypeScript no pudo leer lib.dom.d.ts. Para no alterar la sincronización se usó una copia local en `C:/Users/juanm/AppData/Local/educar-stage4-frontend`, con `npm ci` del mismo lockfile. **169 archivos de src/public/tests y configuración coinciden byte por byte con frontend**. Manifest SHA-256: `fd7b587277bc7fc9d0e87fe53b0271e2ca03e837144d134b9fe74853d0118596`. Allí corren localhost y los comandos frontend aprobados; no se presenta el intento fallido sobre node_modules de OneDrive como aprobado.

Los dos tests PostgreSQL inicialmente no podían iniciar por falta de herramientas locales. Se resolvió fuera del repositorio con herramientas temporales; la ejecución final usa `TEST_PG_BIN=C:/Users/juanm/AppData/Local/educar-stage4-tools/node_modules/@embedded-postgres/windows-x64/native/bin`. No se omitieron tests ni se agregaron dependencias al producto. Sus clústeres descartables se detuvieron y limpiaron. Vite mantiene un aviso de tiempo de plugins; Node avisa sobre VM Modules experimental.

En el navegador integrado se ejecutaron login/logout de los cuatro roles, navegación, servicios académicos, selector familiar, foro, facturación, PDF y CSV. Agenda docente y maestros administrativos conservaron ruta al actualizar. La consola final capturada no mostró errores o warnings. Hubo timeouts/reset de red en intentos de CLI/API y Supabase dashboard; las operaciones aquí declaradas PASS tienen una ejecución posterior exitosa. No se generó un HAR exhaustivo de cada petición.

## 7. Accesos DEMO para la presentación

Superadministrador, Docente, Familia y Alumno: acceso y cierre reales comprobados; permisos y vínculos existentes preservados. Los cuatro botones del footer precargan el login y requieren pulsar Iniciar sesión. No se cambiaron contraseñas ni se crearon usuarios locales.

Usar **localhost ligado a 127.0.0.1** para la presentación actual. El build público sigue sin credenciales. No se habilitó build:demo en ningún alojamiento ni una protección simulada en JavaScript. La documentación previa `frontend/docs/demo-restringida.md` sigue vigente; una presentación alojada con credenciales requerirá comprobar autenticación del servidor también sobre sus assets.

## 8. Git, ramas y commits

| Repositorio | Rama | HEAD conservado |
|---|---|---|
| frontend / educar-cliente | codex/final-presentation-qa | `468bf693f72d5e803b529059199a317da4a36dc7` |
| backend / educar-servidor | codex/final-presentation-qa | `a2a5f424ec0ec5fc4a5bfe092c68bdac010e6c94` |

Remotos verificados: `educar-sistema-escolar/educar-cliente.git` y `educar-sistema-escolar/educar-servidor.git` en GitHub. Se revisaron los inventarios acumulados, los diffs focalizados de esta etapa y candidatos sensibles. Los cambios anteriores se preservaron.

**Commits nuevos: ninguno. Staging: no realizado.** El usuario pospuso commit/push/publicación durante esta sesión. No se hicieron merges, reset ni force push. Los HEAD comparan 0/0 contra las referencias origin/main locales; el fetch de esta sesión falló por reset/DNS, por lo que no se certifica sincronización con el estado remoto actual. Antes de un futuro push habrá que repetir fetch y comparación.

## 9. Push de ambos repositorios

**No ejecutado**, por la instrucción posterior del usuario. No se presenta ningún hash nuevo o publicación GitHub como realizados.

## 10. Vercel y URL

**Despliegue no ejecutado. Sin URL nueva publicada o verificada.** Antes de la pausa se comprobó que dashboard y CLI pedían login; no se creó proyecto ni se cambió configuración o variables remotas. Tras la indicación del usuario se cerró la pestaña Vercel y se continuó solo con Supabase y localhost. La protección real de un host de presentación no fue verificada.

URL local comprobada: `http://127.0.0.1:5175/`. No equivale a una publicación Vercel.

## 11. Evidencia y pendientes

Evidencia local, excluida de Git: `frontend/tmp/etapa4/` contiene capturas, responsive.json, consola, logs finales frontend y manifest de comparación; `backend/tmp/stage4-storage.json` contiene IDs, estados y verificaciones binarias sin tokens. El CSV se descargó en `C:/Users/juanm/Downloads/students_by_course.csv`. Se conservan únicamente comprobantes ficticios asociados, no el PDF temporal. Las capturas y logs no se proponen para commit.

Pendientes explícitos:

1. Commit, push y Vercel: esperar indicación del usuario, repetir fetch/controles y revisar el proyecto existente antes de publicar.
2. Sincronización de OneDrive y recuperación de las dependencias del checkout original. La demo actual usa la copia local idéntica indicada arriba.
3. Nueva invitación Auth y recepción de correo no certificadas; no se enviaron invitaciones de prueba ni correos de cobro.
4. Pasada completa adicional de axe/lector de pantalla y protección remota de presentación no realizadas.

No se amplió el alcance a pantallas familiares de pago, comunicaciones, nuevas pasarelas ni rediseño. La demo local y los datos Supabase están preparados; **la publicación permanece pospuesta**.
