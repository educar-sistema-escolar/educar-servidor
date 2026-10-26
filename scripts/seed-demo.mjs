#!/usr/bin/env node
/**
 * Carga aditiva e idempotente de datos DEMO para la demostracion 2027.
 * No contiene claves ni credenciales. Antes de escribir, genera una copia
 * logica de las tablas afectadas en backend/tmp (directorio ignorado por Git).
 * Ejecutar: node backend/scripts/seed-demo.mjs
 */
import { createInterface } from 'node:readline/promises';
import { stdin, stdout } from 'node:process';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';

const BACKEND_ROOT = resolve(import.meta.dirname, '..');
const ROOT = resolve(BACKEND_ROOT, '..');
const FRONTEND_ENV = resolve(ROOT, 'frontend', '.env');
const BACKUP_DIR = resolve(BACKEND_ROOT, 'tmp');
const YEAR = 2027;
const DEMO_ID = (n) => `d2027000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const TABLES = [
  'profiles', 'people', 'students', 'teachers', 'educational_levels', 'courses',
  'subjects', 'student_enrollments', 'course_subjects', 'student_subject_enrollments',
  'academic_schedules', 'academic_history', 'enrollment_requests', 'student_guardians',
  'sports', 'sport_groups', 'sport_group_schedules', 'student_sport_enrollments',
  'transport_routes', 'transport_stops', 'student_transport_enrollments',
  'dining_services', 'dining_slots', 'student_dining_enrollments', 'dining_usage',
];

function parseEnv(text) {
  const out = {};
  for (const line of text.split(/\r?\n/)) {
    const m = line.match(/^\s*(VITE_SUPABASE_URL|VITE_SUPABASE_ANON_KEY|VITE_SUPABASE_PUBLISHABLE_KEY)\s*=\s*(.*)\s*$/);
    if (m) out[m[1]] = m[2].replace(/^['"]|['"]$/g, '');
  }
  const url = out.VITE_SUPABASE_URL;
  const key = out.VITE_SUPABASE_ANON_KEY || out.VITE_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key) throw new Error('No se encontraron las variables públicas de Supabase en frontend/.env.');
  return { url: url.replace(/\/$/, ''), key };
}

async function hiddenPrompt(question) {
  stdout.write(question);
  if (!stdin.isTTY) throw new Error('La ejecución requiere una terminal interactiva para no guardar credenciales.');
  stdin.setRawMode(true);
  stdin.resume();
  return await new Promise((resolvePrompt, rejectPrompt) => {
    let value = '';
    const onData = (chunk) => {
    for (const char of chunk.toString('utf8')) {
      if (char === '\r' || char === '\n') {
        stdin.off('data', onData);
        stdin.setRawMode(false);
        stdin.pause();
        stdout.write('\n');
        resolvePrompt(value);
        return;
      }
      if (char === '\u0003') {
        stdin.off('data', onData);
        stdin.setRawMode(false);
        stdin.pause();
        rejectPrompt(new Error('Cancelado.'));
        return;
      }
      if (char === '\u007f' || char === '\b') value = value.slice(0, -1);
      else value += char;
    }
    };
    stdin.on('data', onData);
  });
}

const cfg = parseEnv(await readFile(FRONTEND_ENV, 'utf8'));
const rl = createInterface({ input: stdin, output: stdout });
const email = await rl.question('Correo de una cuenta superadmin activa: ');
rl.close();
const password = await hiddenPrompt('Contraseña (no se muestra ni se guarda): ');

async function request(path, { method = 'GET', body, token, headers = {} } = {}) {
  const response = await fetch(`${cfg.url}${path}`, {
    method,
    headers: {
      apikey: cfg.key,
      Authorization: `Bearer ${token || cfg.key}`,
      ...(body === undefined ? {} : { 'Content-Type': 'application/json', Prefer: 'return=representation' }),
      ...headers,
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const text = await response.text();
  let data;
  try { data = text ? JSON.parse(text) : null; } catch { data = text; }
  if (!response.ok) throw new Error(`${method} ${path} devolvio HTTP ${response.status}: ${JSON.stringify(data)}`);
  return data;
}

const auth = await request('/auth/v1/token?grant_type=password', { method: 'POST', body: { email, password } });
if (!auth.access_token) throw new Error('Supabase no devolvio una sesion valida.');
const token = auth.access_token;
const profile = await request('/rest/v1/profiles?select=id,email,role,is_active,account_status&limit=1', { token });
if (profile?.[0]?.role !== 'superadmin' || !profile[0].is_active) {
  throw new Error('La cuenta autenticada no es un superadmin activo; no se guardo respaldo ni se escribieron datos.');
}
const projectRef = new URL(cfg.url).hostname.split('.')[0];
console.log(`Proyecto Supabase validado: ${projectRef}; rol superadmin activo.`);

const snapshot = { created_at: new Date().toISOString(), project_ref: projectRef, tables: {} };
for (const table of TABLES) {
  try {
    snapshot.tables[table] = table === 'enrollment_requests'
      ? await request('/rest/v1/rpc/list_enrollment_requests', { method: 'POST', body: { p_status: null }, token })
      : await request(`/rest/v1/${table}?select=*&limit=10000`, { token });
  } catch (error) {
    throw new Error(`No se completo el respaldo logico de ${table}. No se escribieron datos. ${error.message}`);
  }
}
await mkdir(BACKUP_DIR, { recursive: true });
const backupPath = resolve(BACKUP_DIR, `supabase-demo-before-${new Date().toISOString().replaceAll(':', '-')}.json`);
await writeFile(backupPath, `${JSON.stringify(snapshot, null, 2)}\n`, { flag: 'wx' });
console.log(`Respaldo logico guardado en backend/tmp/${backupPath.split(/[\\/]/).at(-1)} (${Object.values(snapshot.tables).reduce((n, rows) => n + rows.length, 0)} filas).`);
if (!process.argv.includes('--apply')) {
  console.log('Modo seguro: solo se creo el respaldo. Para cargar, volver a ejecutar con --apply.');
  process.exit(0);
}

const confirm = await hiddenPrompt('Escriba APLICAR-DEMO-2027 para autorizar la carga aditiva: ');
if (confirm !== 'APLICAR-DEMO-2027') throw new Error('Confirmacion incorrecta; no se escribieron datos.');

const rpc = (name, body) => request(`/rest/v1/rpc/${name}`, { method: 'POST', body, token });
const rows = (table, filters = '') => request(`/rest/v1/${table}?select=*${filters ? `&${filters}` : ''}&limit=10000`, { token });
const byId = async (table, id) => (await rows(table, `id=eq.${id}`))[0] || null;
const insert = async (table, row) => {
  const result = await request(`/rest/v1/${table}`, { method: 'POST', body: row, token });
  return Array.isArray(result) ? result[0] : result;
};
const update = (table, id, row) => request(`/rest/v1/${table}?id=eq.${encodeURIComponent(id)}`, { method: 'PATCH', body: row, token });
const ensureDeterministic = async (table, id, marker, row) => {
  const found = await byId(table, id);
  if (found) {
    if (found[marker.key] !== marker.value) throw new Error(`Colision ajena a DEMO en ${table}/${id}; se detiene sin sobrescribir.`);
    return found;
  }
  return insert(table, { id, ...row });
};
const profileByEmail = async (value, role) => {
  const found = (await rows('profiles', `email=eq.${encodeURIComponent(value)}&is_active=eq.true`))[0];
  if (!found || found.role !== role) throw new Error(`No se encontro perfil activo con el rol esperado para ${value}; no se cambia el rol.`);
  return found;
};
console.log('Iniciando carga DEMO 2027. Cada fila se inserta solo si no existe su clave DEMO.');
const levels = await rows('educational_levels', 'is_active=eq.true&order=sort_order.asc');
const levelFor = (needle) => levels.find((x) => x.code.toLowerCase().includes(needle) || x.name.toLowerCase().includes(needle));
const initial = levelFor('initial') || levelFor('inicial');
const primary = levelFor('primary') || levelFor('primario') || levelFor('primaria');
const secondary = levelFor('secondary') || levelFor('secundario') || levelFor('secundaria');
if (!initial || !primary || !secondary) throw new Error('No estan disponibles los tres niveles educativos; no se puede continuar.');

const teacherAccounts = [await profileByEmail('profesor@gmail.com', 'teacher')];
const studentAccounts = [
  await profileByEmail('estudiante@gmail.com', 'student'),
  await profileByEmail('profesor@educar.com', 'student'),
  await profileByEmail('luis@educar.com', 'student'),
];
const requestSeeds = [
  ['Pendiente','Demo', '47100001','pending',''],
  ['Aprobada','Demo', '47100002','approved',''],
  ['Rechazada','Demo', '47100003','rejected','Solicitud DEMO de prueba rechazada'],
];
let requestRows = await rpc('list_enrollment_requests', { p_status: null });
const rpcErrors = [];
for (const [first, last, dni, status] of requestSeeds) {
  const marker = `DEMO-2027-REQUEST-${status.toUpperCase()}`;
  const activeConflict = requestRows.find((r) => r.student_dni === dni && ['pending','approved'].includes(r.status) && r.notes !== marker);
  const personConflict = (await rows('people', `dni=eq.${dni}`))[0];
  const ownRequest = requestRows.find((r) => r.notes === marker);
  if (activeConflict || personConflict && !ownRequest) throw new Error(`El DNI sintetico de la solicitud ${first} ya existe; no se escribieron datos adicionales.`);
}
for (let i = 0; i < 5; i++) {
  const collision = (await rows('people', `dni=eq.${42000000 + i}`))[0];
  const owned = (await rows('teachers', `teacher_number=eq.DEMO-2027-D${String(i + 1).padStart(2, '0')}`))[0];
  if (collision && owned?.person_id !== collision.id) throw new Error(`Colision en DNI DEMO de docente; no se escribieron datos adicionales.`);
}
for (let i = 0; i < 14; i++) {
  const collision = (await rows('people', `dni=eq.${43000000 + i}`))[0];
  const owned = (await rows('students', `student_number=eq.DEMO-2027-A${String(i + 1).padStart(3, '0')}`))[0];
  if (collision && owned?.person_id !== collision.id) throw new Error(`Colision en DNI DEMO de alumno; no se escribieron datos adicionales.`);
}

const teacherData = [
  ['Docente', 'Demo Uno', 'DEMO-2027-D01', 'Matemática', teacherAccounts[0].id, 'profesor@gmail.com'],
  ['Docente', 'Demo Dos', 'DEMO-2027-D02', 'Idiomas', null, 'docente02@educar.example'],
  ['Docente', 'Demo Tres', 'DEMO-2027-D03', 'Ciencias Naturales', null, 'docente03@educar.example'],
  ['Docente', 'Demo Cuatro', 'DEMO-2027-D04', 'Lengua y Literatura', null, 'docente04@educar.example'],
  ['Docente', 'Demo Cinco', 'DEMO-2027-D05', 'Educación Física', null, 'docente05@educar.example'],
];
const teachers = [];
for (const [first_name, last_name, teacher_number, specialty, profile_id, email] of teacherData) {
  let teacher = (await rows('teachers', `teacher_number=eq.${encodeURIComponent(teacher_number)}`))[0];
  if (!teacher) {
    const linked = profile_id ? (await rows('people', `profile_id=eq.${profile_id}`))[0] : null;
    if (linked) throw new Error(`El perfil ${email} ya tiene una persona vinculada; se evita reemplazarla.`);
    const created = await rpc('create_teacher', { p_payload: { first_name, last_name, teacher_number, specialty, profile_id, email, dni: String(42000000 + teachers.length) } });
    teacher = (await rows('teachers', `id=eq.${created.id}`))[0];
  } else {
    const person = (await rows('people', `id=eq.${teacher.person_id}`))[0];
    if (person?.first_name !== first_name || person?.last_name !== last_name || person?.profile_id !== profile_id) throw new Error(`El legajo ${teacher_number} ya existe pero no coincide con la identidad DEMO; no se sobrescribe.`);
  }
  if (!teacher) throw new Error(`No se pudo verificar ${teacher_number}.`);
  teachers.push(teacher);
}

const studentNames = [
  ['Alma','Benitez','Inicial'],['Bruno','Cabrera','Inicial'],['Catalina','Dominguez','Inicial'],['Dante','Escobar','Inicial'],
  ['Emilia','Fernandez','Primario'],['Facundo','Gimenez','Primario'],['Guadalupe','Herrera','Primario'],['Hugo','Ibarra','Primario'],['Ines','Juarez','Primario'],
  ['Joaquin','Ledesma','Secundario'],['Kiara','Maidana','Secundario'],['Lautaro','Nuñez','Secundario'],['Milagros','Ortiz','Secundario'],['Nicolas','Perez','Secundario'],
];
const studentProfiles = [studentAccounts[0], studentAccounts[1], studentAccounts[2]];
const students = [];
for (let i = 0; i < studentNames.length; i++) {
  const [first_name, last_name] = studentNames[i];
  const student_number = `DEMO-2027-A${String(i + 1).padStart(3, '0')}`;
  let student = (await rows('students', `student_number=eq.${encodeURIComponent(student_number)}`))[0];
  if (!student) {
    const profile_id = studentProfiles[i]?.id || null;
    const linked = profile_id ? (await rows('people', `profile_id=eq.${profile_id}`))[0] : null;
    if (linked) throw new Error(`El perfil ${studentProfiles[i].email} ya tiene una persona vinculada; se evita reemplazarla.`);
    const created = await rpc('create_student', { p_payload: {
      first_name, last_name, student_number, profile_id,
      email: studentProfiles[i]?.email || `alumno${String(i + 1).padStart(2, '0')}@educar.example`,
      phone: `3624${String(100000 + i).slice(-6)}`,
      dni: String(43000000 + i),
    } });
    student = (await rows('students', `id=eq.${created.id}`))[0];
  } else {
    const person = (await rows('people', `id=eq.${student.person_id}`))[0];
    if (person?.first_name !== first_name || person?.last_name !== last_name || person?.profile_id !== (studentProfiles[i]?.id || null)) throw new Error(`El legajo ${student_number} ya existe pero no coincide con la identidad DEMO; no se sobrescribe.`);
  }
  if (!student) throw new Error(`No se pudo verificar ${student_number}.`);
  const person = (await rows('people', `id=eq.${student.person_id}`))[0];
  if (person && !person.birth_date) await request(`/rest/v1/people?id=eq.${student.person_id}`, {
    method: 'PATCH', body: { birth_date: `${2012 + Math.floor(i / 9)}-03-${String((i % 27) + 1).padStart(2, '0')}` }, token,
  });
  students.push(student);
}

const courseSpecs = [
  { id: DEMO_ID(1), level: initial, code: 'DEMO-27-INI-A', name: 'DEMO Sala de 5 A', year_number: 5, members: [0,1,2,3] },
  { id: DEMO_ID(2), level: primary, code: 'DEMO-27-PRI-A', name: 'DEMO 4to Grado A', year_number: 4, members: [4,5,6,7,8] },
  { id: DEMO_ID(3), level: secondary, code: 'DEMO-27-SEC-A', name: 'DEMO 2do Año A', year_number: 2, members: [9,10,11,12,13] },
];
const courses = [];
for (const spec of courseSpecs) {
  const course = await ensureDeterministic('courses', spec.id, { key: 'code', value: spec.code }, {
    educational_level_id: spec.level.id, code: spec.code, name: spec.name, academic_year: YEAR,
    year_number: spec.year_number, division: 'A', shift: 'morning', capacity: 30, is_active: true,
  });
  if (course.academic_year !== YEAR || course.educational_level_id !== spec.level.id) throw new Error(`Curso DEMO incompatible: ${spec.code}.`);
  courses.push(course);
  for (const i of spec.members) {
    const student = students[i];
    const existing = (await rows('student_enrollments', `student_id=eq.${student.id}&academic_year=eq.${YEAR}&is_active=eq.true`))[0];
    if (existing && existing.course_id !== course.id) throw new Error(`${student.student_number} ya esta inscripto a otro curso 2027; no se modifica.`);
    if (!existing) await insert('student_enrollments', { student_id: student.id, course_id: course.id, academic_year: YEAR, is_active: true });
  }
}

const subjectRows = await rows('subjects', 'is_active=eq.true');
const subjectByText = (q) => subjectRows.find((s) => `${s.code} ${s.name}`.toLowerCase().includes(q));
const math = subjectByText('matematic') || subjectByText('math');
const language = subjectByText('idiom') || subjectByText('lengua') || subjectByText('language');
const science = subjectByText('science') || subjectByText('cienc');
if (!math || !language || !science) throw new Error('Faltan materias base para asignar el plan academico.');
const pe = await ensureDeterministic('subjects', DEMO_ID(20), { key: 'code', value: 'DEMO-EDFI-2027' }, { code: 'DEMO-EDFI-2027', name: 'DEMO Educación Física', is_active: true });
const mappings = [
  [[math,teachers[0]],[language,teachers[1]]],
  [[math,teachers[0]],[science,teachers[2]],[language,teachers[3]]],
  [[science,teachers[2]],[language,teachers[3]],[pe,teachers[4]]],
];
const assignments = [];
for (let c = 0; c < courses.length; c++) {
  for (const [subject, teacher] of mappings[c]) {
    let assignment = (await rows('course_subjects', `course_id=eq.${courses[c].id}&subject_id=eq.${subject.id}&academic_year=eq.${YEAR}&is_active=eq.true`))[0];
    if (assignment && assignment.teacher_id !== teacher.id) throw new Error(`Asignacion 2027 existente para ${subject.name} con otro docente; se detiene.`);
    if (!assignment) assignment = await insert('course_subjects', { course_id: courses[c].id, subject_id: subject.id, teacher_id: teacher.id, academic_year: YEAR, is_active: true });
    assignments.push({ ...assignment, subject, teacher, course: courses[c] });
  }
}
for (let i = 0; i < courses.length; i++) {
  const daily = mappings[i];
  for (let j = 0; j < daily.length; j++) {
    const assignment = assignments.find((a) => a.course.id === courses[i].id && a.subject.id === daily[j][0].id);
    const existing = (await rows('academic_schedules', `course_id=eq.${courses[i].id}&academic_year=eq.${YEAR}&day_of_week=eq.${1 + j}&is_active=eq.true`))[0];
    const startsAt = `${String(8 + j + (i === 1 && j === 0 ? 1 : 0)).padStart(2, '0')}:00:00`;
    const endsAt = `${String(9 + j + (i === 1 && j === 0 ? 1 : 0)).padStart(2, '0')}:00:00`;
    if (!existing) {
      await insert('academic_schedules', { course_id: courses[i].id, course_subject_id: assignment.id, academic_year: YEAR, day_of_week: 1 + j, starts_at: startsAt, ends_at: endsAt, is_active: true });
    } else {
      if (existing.course_subject_id !== assignment.id) throw new Error(`El horario de ${courses[i].name} ya pertenece a otra materia; no se modifica.`);
      if (existing.starts_at !== startsAt || existing.ends_at !== endsAt) {
        await update('academic_schedules', existing.id, { starts_at: startsAt, ends_at: endsAt });
      }
    }
  }
}
for (const student of students) {
  const enrollment = (await rows('student_enrollments', `student_id=eq.${student.id}&academic_year=eq.${YEAR}&is_active=eq.true`))[0];
  for (const assignment of assignments.filter((a) => a.course.id === enrollment.course_id)) {
    const exists = (await rows('student_subject_enrollments', `student_id=eq.${student.id}&course_subject_id=eq.${assignment.id}&academic_year=eq.${YEAR}&is_active=eq.true`))[0];
    if (!exists) await rpc('enroll_student_in_subject', { p_student_id: student.id, p_course_subject_id: assignment.id });
  }
}

const sportsSpec = [
  ['FUTBOL','Fútbol',teachers[4]],['BASQUET','Básquet',teachers[0]],['VOLEY','Vóley',teachers[3]],['NATACION','Natación',teachers[1]],
];
const sportGroups = [];
for (let si = 0; si < sportsSpec.length; si++) {
  const [code,name,teacher] = sportsSpec[si];
  const sport = await ensureDeterministic('sports', DEMO_ID(30 + si), { key: 'code', value: `DEMO-${code}-2027` }, { code: `DEMO-${code}-2027`, name: `DEMO ${name}`, is_active: true });
  for (let li = 0; li < courseSpecs.length; li++) {
    const spec = courseSpecs[li];
    const groupId = DEMO_ID(100 + si * 10 + li);
    const group = await ensureDeterministic('sport_groups', groupId, { key: 'name', value: `DEMO ${name} ${['Inicial','Primario','Secundario'][li]}` }, {
      sport_id: sport.id, name: `DEMO ${name} ${['Inicial','Primario','Secundario'][li]}`, educational_level_id: spec.level.id,
      teacher_id: teacher.id, academic_year: YEAR, capacity: 20, is_active: true,
    });
    if (group.sport_id !== sport.id || group.educational_level_id !== spec.level.id || group.teacher_id !== teacher.id || group.academic_year !== YEAR) {
      throw new Error(`El grupo DEMO ${name} ${['Inicial','Primario','Secundario'][li]} no coincide con sus relaciones esperadas; no se modifica.`);
    }
    const scheduleId = DEMO_ID(200 + si * 10 + li);
    const startsAt = `${String(16 + li).padStart(2, '0')}:00:00`;
    const endsAt = `${String(17 + li).padStart(2, '0')}:00:00`;
    const schedule = await ensureDeterministic('sport_group_schedules', scheduleId, { key: 'sport_group_id', value: group.id }, {
      sport_group_id: group.id, day_of_week: 1 + si, starts_at: startsAt, ends_at: endsAt, is_active: true,
    });
    if (schedule.day_of_week !== 1 + si || schedule.starts_at !== startsAt || schedule.ends_at !== endsAt || !schedule.is_active) {
      await update('sport_group_schedules', schedule.id, { day_of_week: 1 + si, starts_at: startsAt, ends_at: endsAt, is_active: true });
    }
    sportGroups.push({ sport, group, levelIndex: li, sportIndex: si });
  }
}
for (let i = 0; i < students.length; i++) {
  const courseIndex = courseSpecs.findIndex((course) => course.members.includes(i));
  const primaryGroup = sportGroups.find((g) => g.levelIndex === courseIndex && g.sportIndex === i % 4);
  const groupList = [primaryGroup];
  if (i % 3 === 0) groupList.push(sportGroups.find((g) => g.levelIndex === courseIndex && g.sportIndex === (i + 1) % 4));
  for (const g of groupList) {
    const exists = (await rows('student_sport_enrollments', `student_id=eq.${students[i].id}&sport_group_id=eq.${g.group.id}&academic_year=eq.${YEAR}&is_active=eq.true`))[0];
    if (!exists) await rpc('enroll_student_in_sport_group', { p_student_id: students[i].id, p_sport_group_id: g.group.id });
  }
}

const routeNames = ['DEMO Centro - Villa San Martín','DEMO Norte - Barranqueras','DEMO Sur - Fontana','DEMO Oeste - Vilelas'];
const routeStops = [
  ['Plaza 25 de Mayo','Campus Resistencia'],['Terminal Resistencia','Av. Sarmiento'],
  ['Parque 2 de Febrero','Av. Alvear'],['Aeropuerto Resistencia','Ruta 11 km 1000'],
];
const routes = [];
for (let i = 0; i < 4; i++) {
  const existing = (await rows('transport_routes', `route_number=eq.${i + 1}`))[0];
  if (existing && !existing.name.startsWith('DEMO ')) throw new Error(`El recorrido ${i + 1} ya existe y no es DEMO; no se sobrescribe.`);
  const route = existing || await ensureDeterministic('transport_routes', DEMO_ID(300 + i), { key: 'route_number', value: i + 1 }, { route_number: i + 1, name: routeNames[i], capacity: 30, is_active: true });
  routes.push(route);
  for (let j = 0; j < 2; j++) {
    const stopName = routeStops[i][j];
    await ensureDeterministic('transport_stops', DEMO_ID(310 + i * 2 + j), { key: 'name', value: stopName }, { route_id: route.id, name: stopName, stop_order: j + 1, is_active: true });
  }
}
for (let i = 0; i < students.length; i++) {
  const student = students[i], route = routes[i % 4];
  const stop = (await rows('transport_stops', `route_id=eq.${route.id}&stop_order=eq.${(i % 2) + 1}`))[0];
  const exists = (await rows('student_transport_enrollments', `student_id=eq.${student.id}&academic_year=eq.${YEAR}&is_active=eq.true`))[0];
  if (!exists) await insert('student_transport_enrollments', { student_id: student.id, route_id: route.id, stop_id: stop.id, academic_year: YEAR, is_active: true });
  else if (exists.route_id !== route.id) console.log(`Se conserva la asignacion de transporte existente para ${student.student_number}.`);
}

const services = [
  await ensureDeterministic('dining_services', DEMO_ID(400), { key: 'code', value: 'DEMO-ALMUERZO-2027' }, { code: 'DEMO-ALMUERZO-2027', name: 'DEMO Comedor - almuerzo', capacity: 60, is_active: true }),
  await ensureDeterministic('dining_services', DEMO_ID(401), { key: 'code', value: 'DEMO-MERIENDA-2027' }, { code: 'DEMO-MERIENDA-2027', name: 'DEMO Comedor - merienda', capacity: 60, is_active: true }),
];
for (const service of services) for (const date of ['2027-03-01','2027-03-02']) {
  const found = (await rows('dining_slots', `dining_service_id=eq.${service.id}&service_date=eq.${date}`))[0];
  if (!found) await insert('dining_slots', { dining_service_id: service.id, service_date: date, capacity: 60, is_available: true });
}
for (let i = 0; i < students.length; i++) {
  const service = services[i % 2];
  let enrollment = (await rows('student_dining_enrollments', `student_id=eq.${students[i].id}&academic_year=eq.${YEAR}&is_active=eq.true`))[0];
  if (!enrollment) enrollment = await insert('student_dining_enrollments', { student_id: students[i].id, dining_service_id: service.id, academic_year: YEAR, is_active: true });
  for (const date of ['2027-03-01','2027-03-02']) {
    const usage = (await rows('dining_usage', `dining_enrollment_id=eq.${enrollment.id}&service_date=eq.${date}`))[0];
    if (!usage) await rpc('record_dining_usage', { p_dining_enrollment_id: enrollment.id, p_service_date: date, p_used: true });
    else if (usage.used !== true) throw new Error(`El uso DEMO ${date} difiere del fixture; no se modifica.`);
  }
}

for (let i = 0; i < requestSeeds.length; i++) {
  const [first,last,dni,status,reason] = requestSeeds[i];
  const marker = `DEMO-2027-REQUEST-${status.toUpperCase()}`;
  let req = requestRows.find((r) => r.notes === marker);
  if (!req) {
    req = await rpc('submit_enrollment_request', { p_payload: {
      studentFirstName: first, studentLastName: last, studentDni: dni, birthDate: '2018-03-12',
      educationalLevel: 'Primario', schoolYear: '1', turn: 'Mañana', academicYear: YEAR,
      responsibleFullName: 'Familia Demo', responsibleDni: String(44000000 + i), responsibleRelation: 'Madre',
      phone: `362410000${i}`, email: `familia${i + 1}@educar.example`, notes: marker,
    } });
  }
  if (status === 'approved' && req.status === 'pending') {
    try {
      req = await rpc('approve_enrollment_request', { p_request_id: req.id, p_course_id: courses[1].id });
    } catch (error) {
      rpcErrors.push(`approve_enrollment_request: ${error.message}`);
      console.error('La solicitud DEMO de aprobacion queda pendiente: la RPC desplegada falla por una variable SQL ambigua. No se cambia el esquema automaticamente.');
      continue;
    }
  }
  if (status === 'rejected' && req.status === 'pending') req = await rpc('reject_enrollment_request', { p_request_id: req.id, p_reason: reason });
  if (req.status !== status) throw new Error(`La solicitud ${marker} quedo en estado ${req.status}, esperado ${status}.`);
  requestRows.push(req);
}

const reportCodes = [
  'student_overview','students_by_course','students_by_subject','teachers_by_level','teachers_by_level_courses',
  'teachers_by_course_schedule','students_by_sport','students_by_sport_level','students_by_sport_schedule',
  'students_by_sport_schedule_teacher','students_by_transport','transport_and_dining',
];
const reportCounts = {};
for (const code of reportCodes) {
  const result = await rpc('get_admin_report', { p_report_code: code, p_filters: { academic_year: YEAR } });
  reportCounts[code] = Array.isArray(result) ? result.length : result == null ? 0 : 1;
}
const counts = {};
for (const table of ['students','teachers','student_enrollments','student_subject_enrollments','sports','sport_groups','student_sport_enrollments','transport_routes','transport_stops','student_transport_enrollments','dining_services','student_dining_enrollments','dining_usage']) {
  const yearFilter = ['student_enrollments','student_subject_enrollments','student_sport_enrollments','sport_groups','student_transport_enrollments','student_dining_enrollments'].includes(table) ? `academic_year=eq.${YEAR}&` : '';
  const activeFilter = table === 'dining_usage' ? '' : 'is_active=eq.true';
  counts[table] = (await rows(table, `${yearFilter}${activeFilter}`)).length;
}
console.log('Carga terminada. Resultados de los 12 reportes 2027:', JSON.stringify(reportCounts));
console.log('Conteos consultados de tablas principales:', JSON.stringify(counts));
if (rpcErrors.length) console.log('RPCs pendientes de correccion:', JSON.stringify(rpcErrors));
console.log('No se creo el usuario de padre/tutor: hace falta un correo real controlado por ustedes para aceptar la invitacion.');
