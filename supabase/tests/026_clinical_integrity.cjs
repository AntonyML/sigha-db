const assert = require('node:assert/strict');

async function expectSqlState(client, sql, values, expectedCode, label) {
  await client.query('SAVEPOINT migration026_expected_error');
  let caught;
  try {
    await client.query(sql, values);
  } catch (error) {
    caught = error;
  }
  await client.query('ROLLBACK TO SAVEPOINT migration026_expected_error');
  await client.query('RELEASE SAVEPOINT migration026_expected_error');
  assert.equal(caught && caught.code, expectedCode, `${label} must fail with SQLSTATE ${expectedCode}`);
}

async function runMigration026Checks(client) {
  const role = await client.query(
    `SELECT rolcanlogin, rolsuper, rolbypassrls, rolinherit
       FROM pg_roles WHERE rolname = 'sigha_app'`,
  );
  assert.equal(role.rowCount, 1, 'sigha_app role must exist');
  assert.deepEqual(role.rows[0], {
    rolcanlogin: false,
    rolsuper: false,
    rolbypassrls: false,
    rolinherit: false,
  }, 'sigha_app must be a non-login role without RLS bypass');

  const protectedTables = [
    'older_adult', 'clinical_encounters', 'clinical_note_addendums',
    'clinical_scale_evaluations', 'medication_administrations', 'resident_stays',
    'health_lifestyle', 'resident_memos', 'resident_memo_acknowledgments',
    'access_logs', 'sys_audit_logs', 'notifications',
  ];
  const rls = await client.query(
    `SELECT relname, relrowsecurity, relforcerowsecurity
       FROM pg_class
      WHERE relnamespace = 'public'::regnamespace AND relname = ANY($1::text[])`,
    [protectedTables],
  );
  assert.equal(rls.rowCount, protectedTables.length, 'all expected tenant tables must exist');
  for (const table of rls.rows) {
    assert.equal(table.relrowsecurity, true, `${table.relname} must enable RLS`);
    assert.equal(table.relforcerowsecurity, true, `${table.relname} must force RLS`);
  }

  const activeBedConflicts = await client.query(
    `SELECT tenant_id,id_bed
       FROM public.resident_stays
      WHERE id_bed IS NOT NULL AND status IN ('reserved','active','temporary_absence')
      GROUP BY tenant_id,id_bed HAVING count(*) > 1`,
  );
  assert.equal(activeBedConflicts.rowCount, 0, 'an active bed may have only one resident stay');

  const memoTenantColumns = await client.query(
    `SELECT table_name, is_nullable
       FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = ANY($1::text[])
        AND column_name = 'tenant_id'`,
    [['resident_memos', 'resident_memo_acknowledgments']],
  );
  assert.equal(memoTenantColumns.rowCount, 2, 'both memo tables must have a tenant key');
  for (const column of memoTenantColumns.rows) {
    assert.equal(column.is_nullable, 'NO', `${column.table_name}.tenant_id must be mandatory`);
  }

  const memoConstraintNames = [
    'fk_resident_memo_adult_tenant',
    'fk_resident_memo_parent_tenant',
    'fk_memo_ack_memo_tenant',
    'fk_resident_memo_author_tenant',
    'fk_resident_memo_target_user_tenant',
    'fk_resident_memo_resolver_tenant',
    'fk_memo_ack_user_tenant',
  ];
  const memoConstraints = await client.query(
    `SELECT conname FROM pg_constraint
      WHERE conrelid IN ('public.resident_memos'::regclass,
                         'public.resident_memo_acknowledgments'::regclass)
        AND conname = ANY($1::text[])`,
    [memoConstraintNames],
  );
  assert.deepEqual(
    memoConstraints.rows.map((row) => row.conname).sort(),
    [...memoConstraintNames].sort(),
    'memo resident, thread, and actor references must remain in the same tenant',
  );

  const triggerNames = await client.query(
    `SELECT tgname FROM pg_trigger
      WHERE tgrelid = 'public.clinical_encounters'::regclass AND NOT tgisinternal`,
  );
  assert(triggerNames.rows.some((row) => row.tgname === 'trg_prevent_signed_encounter_mutation'),
    '022 encounter immutability must be present through migration 026');

  const org = await client.query(
    `SELECT id FROM public.organizations WHERE slug = 'asopogua'`,
  );
  assert.equal(org.rowCount, 1, 'ASOPOGUA tenant must exist');
  const tenantId = org.rows[0].id;
  const resident = await client.query(
    `SELECT id FROM public.older_adult WHERE tenant_id = $1 ORDER BY id LIMIT 1`,
    [tenantId],
  );
  assert.equal(resident.rowCount, 1, 'development tenant needs a resident for clinical trigger checks');
  const actor = await client.query(
    `SELECT user_id FROM public.organization_members
      WHERE organization_id = $1 ORDER BY user_id LIMIT 1`,
    [tenantId],
  );
  assert.equal(actor.rowCount, 1, 'development tenant needs a member for signature checks');
  const defaultRole = await client.query(
    `SELECT id FROM public.roles WHERE lower(trim(r_name)) = 'not specified'`,
  );
  assert.equal(defaultRole.rowCount, 1, 'the default organization role must exist exactly once');

  const scheduledRows = await client.query(
    `SELECT count(*)::int AS count FROM public.medication_administrations WHERE status::text = 'scheduled'`,
  );
  assert.equal(scheduledRows.rows[0].count, 0, 'scheduled placeholders must be archived, not active events');

  await client.query('BEGIN');
  try {
    await client.query('SET LOCAL ROLE sigha_app');
    await client.query(
      `SELECT set_config('app.current_tenant_id',$1,true), set_config('app.current_user_id',$2,true)`,
      ['2147483647', String(actor.rows[0].user_id)],
    );
    const otherTenantRows = await client.query('SELECT count(*)::int AS count FROM public.older_adult');
    assert.equal(otherTenantRows.rows[0].count, 0, 'RLS must hide residents outside the active tenant');

    await client.query(
      `SELECT set_config('app.current_tenant_id',$1,true), set_config('app.current_user_id',$2,true)`,
      [String(tenantId), String(actor.rows[0].user_id)],
    );
    const visibleTenant = await client.query('SELECT count(*)::int AS count FROM public.organizations');
    assert.equal(visibleTenant.rows[0].count, 1, 'the active organization must remain visible');

    await expectSqlState(
      client,
      'SELECT u_password FROM public.users WHERE id=$1',
      [actor.rows[0].user_id],
      '42501',
      'direct password hash access',
    );
    const initialHash = await client.query(
      'SELECT public.get_current_user_password_hash($1) AS password_hash',
      [actor.rows[0].user_id],
    );
    assert(initialHash.rows[0].password_hash, 'self-service password hash function must return the current hash');
    await client.query(
      'SELECT public.update_current_user_password($1,$2)',
      [actor.rows[0].user_id, 'migration026-test-hash'],
    );
    const updatedHash = await client.query(
      'SELECT public.get_current_user_password_hash($1) AS password_hash',
      [actor.rows[0].user_id],
    );
    assert.equal(updatedHash.rows[0].password_hash, 'migration026-test-hash');

    const uniqueSuffix = `${Date.now()}${Math.floor(Math.random() * 10000)}`;
    const newUser = await client.query(
      `SELECT public.create_tenant_user($1,$2,$3,$4,$5,$6) AS id`,
      [`9${uniqueSuffix}`, 'Migration', 'Test', null, `migration026-${uniqueSuffix}@example.invalid`, 'test-password-hash'],
    );
    const newUserId = newUser.rows[0].id;
    const newUserVisible = await client.query(
      'SELECT id FROM public.users WHERE id=$1',
      [newUserId],
    );
    assert.equal(newUserVisible.rowCount, 1, 'tenant user creation must create a visible member');
    const newMembership = await client.query(
      `SELECT role_id FROM public.organization_members
        WHERE organization_id=$1 AND user_id=$2`,
      [tenantId, newUserId],
    );
    assert.equal(newMembership.rowCount, 1, 'tenant user creation must create a membership');
    assert.equal(Number(newMembership.rows[0].role_id), Number(defaultRole.rows[0].id));

    const memoId = -1 - Math.floor(Math.random() * 1_000_000_000);
    const acknowledgmentId = memoId - 1;
    await client.query(
      `INSERT INTO public.resident_memos (id,tenant_id,older_adult_id,author_id,content)
       VALUES ($1,$2,$3,$4,'Migration tenant-isolation check')`,
      [memoId, tenantId, resident.rows[0].id, actor.rows[0].user_id],
    );
    await client.query(
      `INSERT INTO public.resident_memo_acknowledgments (id,tenant_id,memo_id,user_id)
       VALUES ($1,$2,$3,$4)`,
      [acknowledgmentId, tenantId, memoId, actor.rows[0].user_id],
    );
    const visibleMemo = await client.query(
      'SELECT id FROM public.resident_memos WHERE id=$1',
      [memoId],
    );
    const visibleAcknowledgment = await client.query(
      'SELECT id FROM public.resident_memo_acknowledgments WHERE id=$1',
      [acknowledgmentId],
    );
    assert.equal(visibleMemo.rowCount, 1, 'a memo in the active tenant must be visible');
    assert.equal(visibleAcknowledgment.rowCount, 1, 'a memo acknowledgment in the active tenant must be visible');

    await client.query(
      `SELECT set_config('app.current_tenant_id',$1,true), set_config('app.current_user_id',$2,true)`,
      ['2147483647', String(actor.rows[0].user_id)],
    );
    const hiddenMemo = await client.query(
      'SELECT id FROM public.resident_memos WHERE id=$1',
      [memoId],
    );
    const hiddenAcknowledgment = await client.query(
      'SELECT id FROM public.resident_memo_acknowledgments WHERE id=$1',
      [acknowledgmentId],
    );
    assert.equal(hiddenMemo.rowCount, 0, 'RLS must hide memos outside the active tenant');
    assert.equal(hiddenAcknowledgment.rowCount, 0, 'RLS must hide acknowledgments outside the active tenant');

    await client.query(
      `SELECT set_config('app.current_tenant_id',$1,true), set_config('app.current_user_id',$2,true)`,
      [String(tenantId), String(actor.rows[0].user_id)],
    );

    const encounterId = -1 - Math.floor(Math.random() * 1_000_000_000);
    await client.query(
      `INSERT INTO public.clinical_encounters
         (id,tenant_id,id_older_adult,encounter_type,status,is_signed,signed_at,signed_by,signature_hash,signature_version)
       VALUES ($1,$2,$3,'nursing','signed',TRUE,CURRENT_TIMESTAMP,$4,repeat('a',64),'1')`,
      [encounterId, tenantId, resident.rows[0].id, actor.rows[0].user_id],
    );
    await expectSqlState(
      client,
      `UPDATE public.clinical_encounters SET chief_complaint='mutation attempt' WHERE id=$1`,
      [encounterId],
      '55000',
      'signed encounter update',
    );
    await expectSqlState(
      client,
      'DELETE FROM public.clinical_encounters WHERE id=$1',
      [encounterId],
      '55000',
      'signed encounter deletion',
    );
    await expectSqlState(
      client,
      `INSERT INTO public.clinical_encounters
         (id,tenant_id,id_older_adult,encounter_type,status,is_signed,signed_at,signed_by,signature_hash)
       VALUES ($1,$2,$3,'nursing','signed',TRUE,CURRENT_TIMESTAMP,$4,'bad-hash')`,
      [encounterId - 1, tenantId, resident.rows[0].id, actor.rows[0].user_id],
      '23514',
      'signed encounter with an invalid hash',
    );

    const unsignedEncounterId = encounterId - 3;
    await client.query(
      `INSERT INTO public.clinical_encounters
         (id,tenant_id,id_older_adult,encounter_type,status,is_signed)
       VALUES ($1,$2,$3,'nursing','completed',FALSE)`,
      [unsignedEncounterId, tenantId, resident.rows[0].id],
    );
    await expectSqlState(
      client,
      `INSERT INTO public.clinical_note_addendums
         (tenant_id,id_encounter,author_id,addendum_text,reason_for_addendum,signed_by,signature_hash,signature_version)
       VALUES ($1,$2,$3,'Invalid addendum','Encounter is not signed',$3,repeat('c',64),'1')`,
      [tenantId, unsignedEncounterId, actor.rows[0].user_id],
      '23514',
      'addendum on an unsigned encounter',
    );

    const addendumId = encounterId - 2;
    await client.query(
      `INSERT INTO public.clinical_note_addendums
         (id,tenant_id,id_encounter,author_id,addendum_text,reason_for_addendum,signed_by,signature_hash,signature_version)
       VALUES ($1,$2,$3,$4,'Test addendum','Migration verification',$4,repeat('b',64),'1')`,
      [addendumId, tenantId, encounterId, actor.rows[0].user_id],
    );
    await expectSqlState(
      client,
      `UPDATE public.clinical_note_addendums SET addendum_text='mutation attempt' WHERE id=$1`,
      [addendumId],
      '55000',
      'signed addendum update',
    );
    await expectSqlState(
      client,
      'DELETE FROM public.clinical_note_addendums WHERE id=$1',
      [addendumId],
      '55000',
      'signed addendum deletion',
    );
  } finally {
    await client.query('ROLLBACK');
  }
}

module.exports = { runMigration026Checks };
