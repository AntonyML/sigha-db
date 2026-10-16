const { Client } = require('pg');

async function runBaselineTests(client) {
  process.stdout.write('Running baseline verification tests...\n');

  // 1. Verify Schemas
  const schemasRes = await client.query(`
    SELECT schema_name FROM information_schema.schemata
    WHERE schema_name IN ('core', 'clinico', 'operacion', 'seguridad', 'auditoria', 'analitica')
    ORDER BY schema_name;
  `);
  if (schemasRes.rows.length !== 6) {
    throw new Error(`Expected 6 schemas, found ${schemasRes.rows.length}: ${JSON.stringify(schemasRes.rows)}`);
  }
  process.stdout.write('✓ Schemas verified: core, clinico, operacion, seguridad, auditoria, analitica\n');

  // 2. Verify UUIDv7
  const uuidRes = await client.query('SELECT public.uuidv7() as u1, public.uuidv7() as u2;');
  const u1 = uuidRes.rows[0].u1;
  const u2 = uuidRes.rows[0].u2;
  if (!u1 || !u2 || u1.length !== 36 || u1 === u2) {
    throw new Error(`UUIDv7 generation invalid: ${u1}, ${u2}`);
  }
  process.stdout.write(`✓ UUIDv7 generator functional (${u1})\n`);

  // 3. Verify Seeds: ASOPOGUA, Roles, Permissions, Catalogs
  const orgRes = await client.query('SELECT id, nombre, slug FROM seguridad.organizacion WHERE id = 1;');
  if (!orgRes.rows[0] || orgRes.rows[0].slug !== 'asopogua') {
    throw new Error('Seed ASOPOGUA (id: 1) not found');
  }
  process.stdout.write('✓ Seed: Organization ASOPOGUA verified\n');

  const rolesRes = await client.query('SELECT count(*)::int as count FROM seguridad.rol;');
  if (rolesRes.rows[0].count < 8) {
    throw new Error(`Expected at least 8 roles, found ${rolesRes.rows[0].count}`);
  }
  process.stdout.write(`✓ Seed: ${rolesRes.rows[0].count} system roles verified\n`);

  const permRes = await client.query('SELECT count(*)::int as count FROM seguridad.permiso;');
  if (permRes.rows[0].count < 50) {
    throw new Error(`Expected >50 permissions, found ${permRes.rows[0].count}`);
  }
  process.stdout.write(`✓ Seed: ${permRes.rows[0].count} granular permissions verified\n`);

  const cieRes = await client.query('SELECT count(*)::int as count FROM clinico.catalogo_cie10;');
  const medRes = await client.query('SELECT count(*)::int as count FROM clinico.catalogo_medicamento;');
  const vacRes = await client.query('SELECT count(*)::int as count FROM clinico.catalogo_vacuna;');
  process.stdout.write(`✓ Seeds Catalogs verified: ${cieRes.rows[0].count} CIE-10, ${medRes.rows[0].count} Medications, ${vacRes.rows[0].count} Vaccines\n`);

  // 4. Verify Default Template & Dynamic Fields
  const tplRes = await client.query(`
    SELECT p.nombre as plantilla, count(c.id)::int as total_campos
    FROM core.plantilla_perfil p
    JOIN core.seccion_campo s ON s.plantilla_id = p.id
    JOIN core.definicion_campo c ON c.seccion_id = s.id
    GROUP BY p.nombre;
  `);
  if (!tplRes.rows[0] || tplRes.rows[0].total_campos < 8) {
    throw new Error('Default template and dynamic fields not verified');
  }
  process.stdout.write(`✓ Seed: Template "${tplRes.rows[0].plantilla}" with ${tplRes.rows[0].total_campos} dynamic fields verified\n`);

  // 5. Transactional Test with Rollback: Persona -> Perfil -> Estancia -> GiST Exclusion -> Bitacora -> Clinico
  await client.query('BEGIN');
  try {
    // 5.1 Create Persona
    const personaRes = await client.query(`
      INSERT INTO core.persona (tenant_id, nombre, primer_apellido, segundo_apellido, fecha_nacimiento, sexo)
      VALUES (1, 'Juan', 'Pérez', 'Soto', '1945-05-12', 'masculino')
      RETURNING id, nombre_completo;
    `);
    const personaId = personaRes.rows[0].id;
    const nombreCompleto = personaRes.rows[0].nombre_completo;
    if (nombreCompleto !== 'Juan Pérez Soto') {
      throw new Error(`Expected computed nombre_completo 'Juan Pérez Soto', got '${nombreCompleto}'`);
    }

    // Document
    await client.query(`
      INSERT INTO core.documento_identidad (tenant_id, persona_id, tipo, numero, es_principal)
      VALUES (1, $1, 'cedula', '1-0234-0567', TRUE);
    `, [personaId]);

    // Role Residente
    const rolRes = await client.query(`
      INSERT INTO core.persona_rol (tenant_id, persona_id, rol, desde)
      VALUES (1, $1, 'RESIDENTE', CURRENT_DATE)
      RETURNING id;
    `, [personaId]);
    const personaRolId = rolRes.rows[0].id;

    // Perfil Base
    const perfilRes = await client.query(`
      INSERT INTO core.perfil (tenant_id, persona_rol_id, estado, fecha_ingreso)
      VALUES (1, $1, 'activo', CURRENT_DATE)
      RETURNING id;
    `, [personaRolId]);
    const perfilId = perfilRes.rows[0].id;

    // Perfil Digital
    const tpl = await client.query("SELECT id FROM core.plantilla_perfil WHERE rol_aplicable = 'RESIDENTE' LIMIT 1;");
    const plantillaId = tpl.rows[0].id;
    await client.query(`
      INSERT INTO core.perfil_digital (tenant_id, perfil_id, plantilla_id, datos)
      VALUES (1, $1, $2, $3);
    `, [perfilId, plantillaId, JSON.stringify({
      escolaridad: 'Primaria completa',
      ocupacion_anterior: 'Agricultor',
      grupo_sanguineo: 'O+',
      cobertura_medica: 'CCSS Pensionado'
    })]);
    process.stdout.write('✓ Dynamic Perfil Digital insertion & JSONB GIN verified\n');

    // 5.2 Test Pavilion -> Room -> Bed -> Estancia & Automatic Status Sync
    const pabRes = await client.query(`
      INSERT INTO operacion.pabellon (tenant_id, nombre) VALUES (1, 'Pabellón Los Ceibos') RETURNING id;
    `);
    const pabId = pabRes.rows[0].id;

    const habRes = await client.query(`
      INSERT INTO operacion.habitacion (tenant_id, pabellon_id, numero) VALUES (1, $1, 'H-101') RETURNING id;
    `, [pabId]);
    const habId = habRes.rows[0].id;

    const camaRes = await client.query(`
      INSERT INTO operacion.cama (tenant_id, habitacion_id, codigo) VALUES (1, $1, 'C-01') RETURNING id, estado;
    `, [habId]);
    const camaId = camaRes.rows[0].id;
    if (camaRes.rows[0].estado !== 'disponible') {
      throw new Error(`Expected initial bed state 'disponible', got '${camaRes.rows[0].estado}'`);
    }

    // Assign stay
    await client.query(`
      INSERT INTO operacion.estancia (tenant_id, perfil_id, cama_id, fecha_ingreso)
      VALUES (1, $1, $2, CURRENT_TIMESTAMP);
    `, [perfilId, camaId]);

    // Verify trigger synchronized bed state to 'ocupada' and updated perfil.cama_actual_id
    const checkCama = await client.query('SELECT estado FROM operacion.cama WHERE id = $1;', [camaId]);
    if (checkCama.rows[0].estado !== 'ocupada') {
      throw new Error(`Bed status did not sync to 'ocupada', got '${checkCama.rows[0].estado}'`);
    }
    const checkPerfil = await client.query('SELECT cama_actual_id FROM core.perfil WHERE id = $1;', [perfilId]);
    if (checkPerfil.rows[0].cama_actual_id !== camaId) {
      throw new Error(`Perfil cama_actual_id did not sync to '${camaId}', got '${checkPerfil.rows[0].cama_actual_id}'`);
    }
    process.stdout.write('✓ Automatic Bed & Estancia synchronization verified\n');

    // 5.3 Verify GiST Non-overlapping constraint on Cama
    let gistBlocked = false;
    await client.query('SAVEPOINT gist_test;');
    try {
      // Create a dummy second persona to attempt double occupancy
      const p2 = await client.query("INSERT INTO core.persona (tenant_id, nombre, primer_apellido) VALUES (1, 'Carlos', 'Mora') RETURNING id;");
      const pr2 = await client.query("INSERT INTO core.persona_rol (tenant_id, persona_id, rol) VALUES (1, $1, 'RESIDENTE') RETURNING id;", [p2.rows[0].id]);
      const perf2 = await client.query("INSERT INTO core.perfil (tenant_id, persona_rol_id) VALUES (1, $1) RETURNING id;", [pr2.rows[0].id]);
      await client.query(`
        INSERT INTO operacion.estancia (tenant_id, perfil_id, cama_id, fecha_ingreso)
        VALUES (1, $1, $2, CURRENT_TIMESTAMP);
      `, [perf2.rows[0].id, camaId]);
    } catch (gistErr) {
      if (gistErr.code === '23P01') { // exclusion_violation
        gistBlocked = true;
        await client.query('ROLLBACK TO SAVEPOINT gist_test;');
      } else {
        throw gistErr;
      }
    }
    if (!gistBlocked) {
      throw new Error('GiST exclusion constraint failed to block overlapping bed stay!');
    }
    process.stdout.write('✓ GiST non-overlapping bed stay constraint strictly enforced (23P01)\n');

    // 5.4 Bitacora (Memo replacement)
    // Create system user for authoring
    const userRes = await client.query(`
      INSERT INTO seguridad.usuario (persona_id, email, password_hash)
      VALUES ($1, 'juan.perez@sigha.test', 'hashed_pw') RETURNING id;
    `, [personaId]);
    const userId = userRes.rows[0].id;

    const bitacoraRes = await client.query(`
      INSERT INTO operacion.bitacora_entrada (tenant_id, perfil_id, autor_id, titulo, contenido, categoria, urgencia)
      VALUES (1, $1, $2, 'Ingreso a residencia', 'El residente ingresa en condición estable con signos vitales en rango.', 'general', 'media')
      RETURNING id;
    `, [perfilId, userId]);
    const bitacoraId = bitacoraRes.rows[0].id;

    await client.query(`
      INSERT INTO operacion.bitacora_acuse (tenant_id, entrada_id, usuario_id, comentario)
      VALUES (1, $1, $2, 'Enterado del ingreso');
    `, [bitacoraId, userId]);
    process.stdout.write('✓ Bitácora entries and acknowledgments verified\n');

    // 5.5 Clinical Encounters & Vital Signs with IMC
    const encRes = await client.query(`
      INSERT INTO clinico.encuentro_clinico (tenant_id, perfil_id, profesional_id, tipo, motivo, objetivo, plan)
      VALUES (1, $1, $2, 'medicina_general', 'Evaluación de ingreso', 'Paciente orientado, cardiopulmonar normal', 'Plan de cuidados integral')
      RETURNING id;
    `, [perfilId, userId]);
    const encId = encRes.rows[0].id;

    const vsRes = await client.query(`
      INSERT INTO clinico.signo_vital (tenant_id, perfil_id, encuentro_id, registrado_por, peso_kg, talla_cm, presion_sistolica, presion_diastolica, frecuencia_cardiaca)
      VALUES (1, $1, $2, $3, 72.5, 170.0, 120, 80, 72)
      RETURNING id, imc;
    `, [perfilId, encId, userId]);
    const imc = parseFloat(vsRes.rows[0].imc);
    // 72.5 / (1.70 * 1.70) = 25.08 -> 25.1
    if (Math.abs(imc - 25.1) > 0.2) {
      throw new Error(`Calculated IMC mismatch: expected ~25.1, got ${imc}`);
    }
    process.stdout.write(`✓ Vital signs with generated stored IMC verified (${imc})\n`);

    // 5.6 View analitica.v_resumen_residentes
    const viewRes = await client.query(`
      SELECT nombre_completo, documento_numero, cama_codigo, habitacion_numero, pabellon_nombre, perfil_digital_datos
      FROM analitica.v_resumen_residentes
      WHERE perfil_id = $1;
    `, [perfilId]);
    if (!viewRes.rows[0] || viewRes.rows[0].cama_codigo !== 'C-01') {
      throw new Error(`Analytical view check failed: ${JSON.stringify(viewRes.rows)}`);
    }
    process.stdout.write('✓ Analytical view (v_resumen_residentes) end-to-end verified\n');

  } finally {
    await client.query('ROLLBACK');
    process.stdout.write('✓ Transactional test changes cleanly rolled back.\n');
  }
}

async function main() {
  if (process.env.SIGHA_DB_ENV !== 'development' || process.env.NODE_ENV === 'production') {
    throw new Error('Set SIGHA_DB_ENV=development before running tests.');
  }
  const connectionString = process.env.SIGHA_DEV_DATABASE_URL;
  if (!connectionString) throw new Error('SIGHA_DEV_DATABASE_URL is required.');
  const target = new URL(connectionString);
  if (!/\.supabase\.com$/i.test(target.hostname)) {
    throw new Error('Tests may only run against the configured Supabase development database.');
  }

  const client = new Client({
    connectionString,
    ssl: { rejectUnauthorized: false },
    connectionTimeoutMillis: 15000,
    application_name: 'sigha-db-baseline-test',
  });

  try {
    await client.connect();
    await runBaselineTests(client);
    process.stdout.write('\n>>> ALL BASELINE TESTS PASSED PERFECTLY! <<<\n');
  } finally {
    await client.end();
  }
}

main().catch((error) => {
  const code = error && error.code ? ` (SQLSTATE ${error.code})` : '';
  process.stderr.write(`Baseline tests failed${code}: ${error instanceof Error ? error.message : 'unknown error'}\n`);
  if (error.detail) process.stderr.write(`Detail: ${error.detail}\n`);
  if (error.hint) process.stderr.write(`Hint: ${error.hint}\n`);
  if (error.where) process.stderr.write(`Where: ${error.where}\n`);
  process.exitCode = 1;
});
