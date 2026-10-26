# RESUMEN ETAPA 3 — QA final y preparación para GitHub

Fecha: 26/10/2026, America/Buenos_Aires. Proyecto Supabase verificado: `nhwsgmijdsxzuxgpllhy`, CentroEducativo / mmoschen's Project / main.

**Resultado:** foro y facturación ya tienen estructura real y responden sin los 404 detectados; se corrigieron votos, ciclo de transporte, responsable deportivo, filtros/exportación, estados de autenticación y detalles de accesibilidad. Los recorridos probados son utilizables. El alcance y los límites de pruebas se distinguen abajo; no se declara una certificación integral de todo el producto.

**Conservación:** no se ejecutaron seed ni provisión de cuentas, no se cambiaron credenciales y no quedaron nuevos registros DEMO. Se conservaron el diseño de Etapa 2, los 16 alumnos, 6 docentes, 2 hijos de la familia, horarios y servicios existentes. No se ejecutaron commit, push, merge ni deploy de frontend/Edge Functions. Las tres migraciones incrementales de esta etapa sí se aplicaron a Supabase, dentro del alcance solicitado.

## 1. Documentos y método

Se leyeron los cierres de Etapas 1 y 2, INFORME_CAMBIOS_Y_PENDIENTES.md y la auditoría histórica RF-01 a RF-23. Los datos posteriores de Etapas 1/2 prevalecen sobre la auditoría del 25/10. Se inspeccionaron rutas, servicios, migraciones y catálogos remotos antes de modificar.

Se usó el frontend local Vite en `http://127.0.0.1:5175` y el navegador integrado conectado a Supabase. El primer intento con Edge de escritorio no pudo verificar su URL y se detuvo; el navegador integrado sí conservaba la sesión del SQL Editor y permitió completar el trabajo remoto. No fue necesario pedir ni guardar otra credencial administrativa.

Las pruebas de escritura remotas usan las identidades institucionales existentes y `SET LOCAL ROLE authenticated`, con `auth.uid()` derivado de su perfil. Terminan en ROLLBACK. No se confunde una consulta postgres privilegiada con una sesión de alumno/familia. La fila de Storage usada para comprobar el contrato del comprobante fue metadata transaccional, no un archivo subido: se aclara esa limitación en facturación.

## 2. Problemas identificados y solucionados

| Problema | Causa comprobada | Corrección |
|---|---|---|
| Foro HTTP 404/PGRST205 | No existían tablas de foro en el esquema real; no era una referencia errónea del frontend | Recuperación incremental del módulo existente con tablas, índices, funciones, triggers y RLS |
| Facturación HTTP 404/PGRST205 | No existían tablas de facturas, valores, transferencias ni comprobantes | Misma recuperación para el módulo financiero, conservando su arquitectura y bucket privado |
| Cambiar voto fallaba con 42703 | Un trigger compartido referenciaba reply_id sobre un registro de votos de discusión | Separar las sentencias por tipo de tabla; regresión de ambos tipos de voto |
| Transporte siempre usaba el año actual | RPC de 3 argumentos usaba current_date, sin selección de ciclo en UI | Nueva firma de 4 argumentos con ciclo explícito, formulario y repositorio actualizados; se conserva la firma legacy para clientes del ciclo actual |
| Grupo deportivo activo sin responsable | teacher_id nullable sin restricción condicional | CHECK para grupo activo y profesor obligatorio en formulario; ningún grupo existente requirió modificación |
| Login podía esperar indefinidamente | Inicialización/consultas SDK y red no tenían límite de espera de la aplicación | Red con aborto a 15 s; operaciones Auth e inicialización acotadas a 20 s; errores terminan validación y permiten reintento |
| Filtros incompatibles se enviaban como si aplicaran | La UI mostraba todos los filtros para todos los códigos | Matriz por familia y saneamiento en repositorio; se limpian al cambiar tipo; resumen global identificado como tal |
| Respuestas de reportes fuera de orden | Una consulta anterior podía reemplazar la selección reciente | Secuencia de solicitudes, limpieza al consultar y exportación bloqueada durante carga/error |
| CSV no escapaba comillas según CSV | JSON.stringify no es un escape RFC 4180 | Escape de comillas dobles, CRLF y protección frente a fórmulas de planilla |
| Números de materias con bajo contraste | Opacidad excesiva | Contraste corregido y nueva pasada axe sin esa infracción |
| Etiqueta de materias sin rol y pestañas incompletas | aria-label en div genérico; faltaba navegación de tabs | role=group y tabpanel/aria-controls con flechas, Inicio/Fin y foco verificables |

## 3. Migraciones remotas

El preflight encontró **cero tablas** con los nombres de los módulos ausentes y solo las seis versiones registradas al cierre de Etapa 1. Sus dependencias de identidad, alumnos, profesores y servicios ya existían. No se ejecutó db push, db reset ni una cadena histórica completa.

| Versión nueva | Archivo | Resultado y MD5 normalizado verificado |
|---|---|---|
| 20261026150000 | recover_missing_forum_billing.sql | Aplicada; `228a2cb26966e3f0c307ddefe3575307` |
| 20261026151000 | fix_forum_vote_record.sql | Aplicada; `fbc6cb72c9b1e68e5988f4643c3eb706` |
| 20261026152000 | transport_cycle_sport_teacher.sql | Aplicada; `bdfb59f96c54629df54a7f8140250720` |

La recuperación reutiliza explícitamente las definiciones versionadas de foro y facturación, incluidos sus arreglos de integridad y seguridad. Solo crea un módulo cuando sus tablas están completamente ausentes; si existe completo no hace nada, y ante un módulo parcial aborta para exigir inspección. También se probó como no-op en PostgreSQL con ambos módulos completos. No registra versiones históricas que no se ejecutaron por separado. Las tres versiones nuevas se registraron con su fuente SQL y se contrastaron contra el archivo local. La recarga del schema cache se solicita con NOTIFY.

Se crearon las estructuras de calendario/cola de recordatorios que forman parte del módulo versionado; no se instaló cron, no se desplegó el worker ni se envió correo. No se conectó ninguna pasarela de pagos.

Postflight: RLS activa en las diez tablas comprobadas de foro/facturación. Foro, respuestas, valores, facturas, transferencias y comprobantes tienen **0 filas persistidas** al terminar. Alumnos=16, docentes=6, hijos de la familia=2. No quedaron datos de prueba adicionales.

## 4. Foro estudiantil

**Estado funcional:** listado real sin error y estado vacío correcto. Crear discusión, asignar autor desde Auth, responder, contar respuestas, votar, cambiar y retirar voto, votar respuesta y validar título vacío se probaron en Supabase real. Padres y docentes no ven discusiones; publicar como parent y consultar sin sesión se rechaza/oculta según privilegios y RLS. Las pruebas temporales se revirtieron.

En navegador: login alumno, acceso a foro, categorías/orden/búsqueda visibles, diálogo de publicación, foco inicial y Escape. No se publicó contenido persistente ni se inventaron discusiones DEMO. Por eso no se afirma haber recorrido visualmente una discusión persistida con respuestas; la integración de esas operaciones fue SQL real y pruebas PostgreSQL.

## 5. Facturación

**Estado funcional:** administración carga valores, selector de 16 alumnos y transferencias pendientes sin 404. El reporte financiero responde con conjuntos vacíos cuando no existen facturas, como corresponde a la indicación de no agregar datos.

Prueba real con ROLLBACK: precios temporales para servicios ya existentes, emisión mensual para una hija vinculada, ítems calculados, duplicado rechazado, acceso familiar propio, configuración privada oculta, emisión denegada a familia y lectura denegada a docente. Presentación de transferencia por RPC, repetición idempotente, estado pendiente sin imputación de pago, aprobación parcial con asignación de 5000 centavos y segunda aprobación rechazada. Toda esa información se revirtió.

Los tests PostgreSQL locales además verifican factura ajena, ítem de otra factura, conservación del precio emitido, evidencia adjunta protegida, identidad revocada y concurrencia de dos conexiones. Son pruebas con esquema de compatibilidad de plataforma, no una ejecución del servidor Storage real.

**Límite explícito:** el contrato remoto del comprobante se probó con metadata de `storage.objects` dentro de la transacción. No se subió ni descargó un PDF/JPG real ni se abrió un comprobante mediante URL firmada; no se afirma que esa parte esté probada de punta a punta. La UI familiar web actual no tiene una pantalla de pagos: se conservaron los alcances ya existentes; la lectura/presentación familiar de facturación corresponde a las API y cliente móvil existente, fuera de este QA web.

## 6. Autenticación

Se conservaron Supabase Auth, las cuentas y sus roles. No se incorporó autenticación local ni credenciales alternativas.

- Acceso y cierre de sesión reales con administrador, docente, familia y alumno.
- Recarga en docente, familia y foro mantiene el acceso correspondiente; administrador también conserva su sesión al recargar.
- Prueba de red desconectada en el navegador: el formulario muestra error y vuelve a habilitarse. Se restauró la red y un acceso posterior volvió a entrar al panel administrativo. Se mejoró el mensaje para distinguir red de credenciales rechazadas.
- Los tests cubren inicialización que nunca resuelve, rechazo de red, reintento posterior, perfil suspendido/inactivo, sesión expirada sin usuario y aislamiento del portal administrativo.
- Se preservó el callback Auth diferido, para no ejecutar consultas de sesión dentro del callback síncrono del SDK. El layout docente redirige al login si la sesión ya no está disponible, en lugar de quedar preparando el espacio.

La reproducción de red caída demuestra la recuperación del estado de UI; no prueba que todos los escenarios posibles de proveedor/renovación simultánea estén agotados. La expiración de token se simuló en test del servicio, no esperando a que expire una sesión real durante una hora.

## 7. Requerimientos RF-01 a RF-23

“Completado y probado” se refiere al alcance institucional de ese requerimiento y a la evidencia indicada, sin convertirlo en una auditoría exhaustiva de toda la aplicación. Se conservan categorías parciales cuando falta cobertura. No se crearon datos DEMO permanentes para completar pruebas pendientes.

| RF | Requerimiento | Estado | Evidencia y límites |
|---|---|---|---|
| RF-01 | Registro y solicitud de alumno | **Implementado, parcialmente probado** | Formulario/RPC existentes; altas DEMO previas y solicitud aprobada persistida verificadas. Rechazo y prevención de duplicados comprobados. No se envió una nueva solicitud desde el frontend en esta etapa. |
| RF-02 | Consulta de alumno | **Completado y probado** | Administración y API conservan 16 alumnos; portal del alumno y ficha familiar consultan datos reales. |
| RF-03 | Modificación de alumno | **Completado y probado** | stage3-masterdata.sql modifica el teléfono de un alumno existente, verifica el cambio y rechaza DNI duplicado; ROLLBACK. |
| RF-04 | Aprobación y estado | **Completado y probado** | Etapa 1: aprobación idempotente persistida. En esta etapa se revalidaron sus IDs y unicidad; rechazo repetido y reaprobar rechazado se probaron con ROLLBACK. |
| RF-05 | Registro de profesor | **Implementado, parcialmente probado** | Se conservan 6 docentes creados previamente por RPC. Lectura, actualización y rechazo de alta con DNI duplicado probados; no se creó un profesor adicional ni se recorrió un alta nueva por UI. |
| RF-06 | Consulta de profesor y materias | **Completado y probado** | Docente real: 2 materias, 2 cursos, listado de alumnos, búsqueda y agenda. Nombre institucional resuelto desde people. |
| RF-07 | Modificación de profesor | **Completado y probado** | Cambio de especialidad y verificación con ROLLBACK; llamada de modificación sin rol administrativo rechazada con 42501. |
| RF-08 | Deporte y responsable | **Completado y probado** | 12 grupos existentes conservados. Nueva restricción impide grupos activos sin profesor; validación y campo obligatorio en UI; caso negativo SQL real. |
| RF-09 | Grupos por nivel y horario | **Completado y probado** | Datos reales por nivel, rechazo de solapamiento deportivo y docente en SQL real; horarios DEMO intactos y tests PostgreSQL. |
| RF-10 | Inscripción deportiva | **Completado y probado** | RPC real: alta transaccional, duplicado, máximo de dos deportes y cupo lleno. Cruces de horarios verificados en aceptación de Etapa 1 y PostgreSQL. Todo revertido. |
| RF-11 | Transporte y cuatro recorridos | **Completado y probado** | 4 recorridos existentes. Alta para ciclo 2027, duplicado, cupo lleno, parada ajena y quinto recorrido inválido probados con ROLLBACK. UI ahora envía ciclo seleccionado. |
| RF-12 | Comedor | **Completado y probado** | Alta transaccional, duplicado y cupo lleno; upsert used=true/false probado en Etapa 1 y PostgreSQL; postflight conserva el registro y estado existentes. |
| RF-13 | Usuarios y roles | **Implementado, parcialmente probado** | Cuatro sesiones reales y redirecciones correctas; tests de autorización/provisión. No se envió una invitación ni se creó una cuenta Auth nueva por indicación de conservar las existentes. |
| RF-14 | Padres/tutores e hijos | **Completado y probado** | Familia real conserva exactamente 2 hijos. Selector, fichas, RLS y vínculo idempotente transaccional probados. Hijo ajeno oculto. |
| RF-15 | Permisos por rol | **Implementado, parcialmente probado** | Guards, RLS y denegación de RPC probados con sesiones reales. Foro restringido a alumnos; facturas restringidas a familia vinculada/admin. No se agotó cada combinación de política y mutación de todas las tablas. |
| RF-16 | Niveles educativos | **Implementado, parcialmente probado** | Tres niveles existentes consultados en UI/API y filtros reales. No se ejecutó un ciclo completo de alta/edición/desactivación de nivel. |
| RF-17 | Cursos y nivel | **Implementado, parcialmente probado** | Cursos y matrículas reales; unicidad de matrícula por ciclo y pertenencia al curso probadas. No se agotó el CRUD de cursos en UI. |
| RF-18 | Materias | **Implementado, parcialmente probado** | Materias y asignaciones reales consultadas; duplicado de código rechazado. No se agotó el CRUD de materias en UI. |
| RF-19 | Horarios | **Completado y probado** | Solapamiento académico rechazado 23P01, adyacencia aceptada y horario Primario 09:00–10:00 intacto. Repetición SQL real con ROLLBACK. |
| RF-20 | Inscripción al cursado | **Completado y probado** | Alta por RPC real, duplicado y alumno de curso ajeno verificados con ROLLBACK; materias/historial visibles en portales. |
| RF-21 | Profesor, materia y curso | **Completado y probado** | Asignaciones reales y agenda docente; reasignación incompatible rechazada 23P01. Pruebas PostgreSQL y aceptación remota. |
| RF-22 | Doce reportes administrativos | **Completado y probado** | 105 consultas reales; combinaciones válidas iguales a intersecciones exactas de filas; 12 CSV descargados y parseados; responsive y controles no aplicables deshabilitados. |
| RF-23 | Asistente deportivo | **Completado y probado** | RF-23 existente preservado. Integración real verificada en Etapa 2 y reglas positivas/negativas incluidas en los tests actuales. No matricula automáticamente ni incorpora servicios de IA externos. |

Ninguno de estos 23 requisitos se detectó totalmente sin implementación en el alcance actual. Eso no convierte los parcialmente probados en completos. La clasificación “Parcial o simulado” aplica a comportamientos adicionales de la demo descritos en pendientes, no al reemplazo de datos Supabase de los módulos aquí corregidos.

## 8. Doce reportes, filtros y CSV

Se verificaron **105 consultas reales** con `scripts/verify-stage3-live.mjs`: base sin filtros, ciclo 2027, ciclo inexistente y cada combinación aplicable de los 3 niveles, 4 deportes y 4 recorridos. El resultado de cada combinación se comparó con la intersección exacta de filas de la base del mismo ciclo; no se consideró suficiente recibir HTTP 200.

| Código | Filas sin filtros | Filas ciclo 2027 | Filtros habilitados | CSV descargado y parseado |
|---|---:|---:|---|---|
| `student_overview` | 16 | No aplica | Ninguno: resumen global | Sí |
| `students_by_course` | 16 | 15 | Ciclo + nivel | Sí |
| `students_by_subject` | 38 | 38 | Ciclo + nivel | Sí |
| `teachers_by_level` | 11 | 8 | Ciclo + nivel | Sí |
| `teachers_by_level_courses` | 11 | 8 | Ciclo + nivel | Sí |
| `teachers_by_course_schedule` | 8 | 8 | Ciclo + nivel | Sí |
| `students_by_sport` | 19 | 19 | Ciclo + nivel + deporte | Sí |
| `students_by_sport_level` | 19 | 19 | Ciclo + nivel + deporte | Sí |
| `students_by_sport_schedule` | 19 | 19 | Ciclo + nivel + deporte | Sí |
| `students_by_sport_schedule_teacher` | 19 | 19 | Ciclo + nivel + deporte | Sí |
| `students_by_transport` | 14 | 14 | Ciclo + recorrido | Sí |
| `transport_and_dining` | 14 | 14 | Ciclo + recorrido | Sí |

El resumen por alumno incluye todos los ciclos: la UI lo dice y deshabilita los cuatro filtros; el repositorio no los envía. No se cambió la semántica del reporte global para fingir un filtrado. Transporte no ofrece filtro por nivel/deporte; deportes no ofrece recorrido; reportes académicos no ofrecen deporte/recorrido. No se añadió ningún reporte.

Las doce exportaciones se descargaron desde el botón real y se analizaron con un parser CSV: conteos de filas y número de columnas coinciden con los resultados de la API. También se descargó alumnos por curso filtrado a 2027: 15 filas más cabecera. Los tests del serializador verifican comas, comillas, saltos de línea y fórmulas. Se corrigieron columnas de apellido/nombre que el reporte por curso realmente devuelve y antes no se mostraban.

## 9. Accesibilidad, responsive y navegador

Se conservó el layout institucional de Etapa 2. Se realizaron capturas reales y mediciones en **390, 768 y 1440 px** de docente, familia, alumno, reportes, facturación y foro. En las mediciones guardadas, scrollWidth no supera clientWidth; las tablas mantienen su desplazamiento interno. Administración principal tiene además captura de escritorio; sus anchos base se habían probado en Etapa 2.

Se probaron selector de hijos, navegación principal, pestañas de servicios, formularios, errores sin envío, diálogo del foro y teclado del drawer. Flechas cambian de Transporte a Comedor; Inicio vuelve a Deportes. Foco visible, cierre con Escape y retorno al botón preservados.

Se utilizó **axe-core 4.14.0** como herramienta temporal dentro de `tmp`, sin instalarla como dependencia del producto. Se ejecutaron reglas WCAG 2 A/AA, 2.1 AA y 2.2 AA sobre los paneles cargados. Detectó dos contrastes insuficientes en números docentes, corregidos y revalidados, y una etiqueta de grupo sin rol, corregida. Familia, alumno, reportes y facturación devolvieron cero infracciones en sus pasadas; docente quedó sin infracciones de contraste. Administración y foro devolvieron comprobaciones de contraste/atributos pendientes de revisión manual (incomplete), no una aprobación automática de esos casos.

No se certifica WCAG completa ni se probó con lector de pantalla. No se agotaron todos los formularios, estados y tablas de todas las rutas. No se recorrió el flujo de subida de archivos ni una escritura institucional persistente desde UI, para conservar los datos existentes.

Durante los recorridos normales no se observaron excepciones nuevas en consola. La prueba deliberada offline produce errores de red esperados; no se cuentan como una regresión. Los anteriores 404 de foro/facturación desaparecieron y las verificaciones API posteriores terminaron correctamente.

Evidencias ignoradas por Git: `frontend/tmp/etapa3/` contiene capturas por ancho, las 12 exportaciones, `csv-verification.json` y `qa-browser.json`; `backend/tmp/` contiene resultados de pre/postflight y verificaciones remotas. Las capturas son del navegador real, no mockups. No se publican credenciales en este informe.

## 10. Validaciones técnicas finales

| Validación | Resultado |
|---|---|
| Frontend npm run lint | Aprobado, sin errores ni warnings |
| Frontend npm run build | Aprobado, TypeScript + Vite |
| Frontend npm test | 18/18 aprobadas |
| Backend node --test tests/*.test.mjs | 17/17 aprobadas, incluidos PostgreSQL, votos y ciclo de transporte |
| Backend SQL remoto | stage3-modules-acceptance.sql, stage3-academic-services.sql, stage3-masterdata.sql y stage1-live-acceptance.sql: aprobados con ROLLBACK |
| Backend verificación API | verify-stage1-live.mjs (solo lectura) y verify-stage3-live.mjs: aprobadas |
| CSV | 12/12 exportaciones reales coinciden en filas y columnas |
| Secretos en producción | 69 archivos revisados; 8 valores DEMO configurados ausentes; ninguna clave de servidor detectada |
| git diff --check | Aprobado en ambos; aviso preexistente LF/CRLF de RegistrationPage.tsx |

La primera ejecución de backend falló al superar 60 s inicializando dos clústeres PostgreSQL bajo carga de Windows. Se aumentó el límite del proceso de test a 180 s, conservando errores y assertions; las siguientes ejecuciones serial y estándar terminaron con 17/17. No se ocultó ni omitió el test. Vite mantiene una advertencia de tiempo de plugins y Node avisa que VM Modules es experimental; no son errores de tests.

No se ejecutaron suites pgTAP completas ni se levantó toda la plataforma Supabase local. Las pruebas SQL remotas y PostgreSQL descriptas constituyen evidencia distinta de los tests unitarios.

## 11. Pendientes reales y prioridad

| Prioridad | Pendiente | Impacto |
|---|---|---|
| P2 | Subida/lectura de un comprobante binario real mediante Storage y URL firmada, con cliente familiar | API, RLS y contrato probados; integración de archivo no certificada |
| P2 | Invitación/provisión de nueva cuenta y recepción de correo | No se ejecutó para no crear cuentas ni enviar comunicaciones; cuatro cuentas existentes operativas |
| P2 | Completar cobertura de CRUD de niveles/cursos/materias y envío público desde UI | Se conservaron las funciones existentes; matriz RF indica cobertura parcial |
| P2 | Revisión manual restante de axe incomplete y lector de pantalla | No hay certificación exhaustiva de accesibilidad |
| P3 | Asistencia/comunicaciones de la ficha, comentarios/opiniones/noticias según limitaciones de la auditoría previa | Son alcances adicionales parciales/locales; esta etapa no los convirtió en módulos institucionales completos |
| P3 | Operación de recordatorios por correo/cron y protección del host de presentación | No se configuraron envíos, scheduler ni publicación; fuera del alcance de la demo académica actual |
| P3 | Historial remoto antiguo incompleto | Se registró solo lo aplicado y comprobado; no se inventaron versiones ni se reconstruyó toda la base |

No quedan los bloqueos 404 de foro/facturación. No se declara “todo el proyecto terminado” ni se ocultan los límites anteriores.

## 12. Git y preparación para publicar

Se hizo fetch de ambos origin y se verificaron los destinos:

- Frontend: `https://github.com/educar-sistema-escolar/educar-cliente.git`, HEAD `468bf69`.
- Backend: `https://github.com/educar-sistema-escolar/educar-servidor.git`, HEAD `a2a5f42`.
- Ambas ramas: `codex/final-presentation-qa`. HEAD frente a origin/main: **0 adelantados / 0 atrasados** en ambos repositorios, tras fetch. Las modificaciones de las tres etapas aún no están en commits. Estas ramas no tienen upstream propio configurado.

Se revisaron inventarios de archivos modificados/nuevos y diffs de las tres etapas, sus rutas, compilación y pruebas. Se comprobó el conjunto candidato de archivos versionados/nuevos contra los secretos configurados y patrones de claves privadas: sin coincidencias. `.env`, `.env.local`, temporales, backups, capturas y dist no están versionados; backend también excluye `.env.*`, conservando `.env.example`. Los ejemplos de configuración son plantillas, no contienen valores reales. No se ejecutó el seed durante esta etapa.

Los cambios previos se preservaron, incluido el retiro del login local, RF-23 y la unificación visual. No se hicieron git add, commit, push, merges, resets ni deploys. Quedan listos para revisión y posterior staging/commit autorizado. La lista completa actual se encuentra en `REVISION_PARA_GITHUB.md` de cada repositorio.

Mensajes de commit propuestos, separados:

**Frontend**

```text
Unificar paneles institucionales y cerrar validaciones de acceso y reportes

- Consolidar layout por rol y controles accesibles.
- Preservar RF-23 y restringir credenciales DEMO al entorno habilitado.
- Acotar esperas de Auth y corregir filtros, CSV y ciclo de transporte.
- Incorporar pruebas y documentación de las tres etapas.
```

**Backend**

```text
Completar foro y facturacion y validar reglas academicas

- Incorporar correcciones incrementales de inscripciones, tutores y horarios.
- Recuperar modulos ausentes con RLS y corregir votos del foro.
- Respetar ciclo de transporte y exigir responsable deportivo.
- Ampliar regresiones PostgreSQL y aceptacion remota con rollback.
```

Este informe se guarda en el directorio padre y como copia versionable en frontend/docs y backend/docs/operations. El directorio padre no es la raíz de ninguno de los dos repositorios.
