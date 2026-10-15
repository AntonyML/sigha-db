const assert = require('node:assert/strict');

async function expectSqlState(client, sql, values, expectedCode, label) {
  await client.query('SAVEPOINT migration029_expected_error');
  let caught;
  try {
    await client.query(sql, values);
  } catch (error) {
    caught = error;
  }
  await client.query('ROLLBACK TO SAVEPOINT migration029_expected_error');
  await client.query('RELEASE SAVEPOINT migration029_expected_error');
  assert.equal(caught && caught.code, expectedCode, `${label} must fail with SQLSTATE ${expectedCode}`);
}

async function enumLabels(client, name) {
  const result = await client.query(
    `SELECT e.enumlabel
       FROM pg_type t
       JOIN pg_namespace n ON n.oid = t.typnamespace
       JOIN pg_enum e ON e.enumtypid = t.oid
      WHERE n.nspname = 'public' AND t.typname = $1
      ORDER BY e.enumsortorder`,
    [name],
  );
  return result.rows.map((row) => row.enumlabel);
}

async function runMigration029Checks(client) {
  assert.deepEqual(
    await enumLabels(client, 'e_organization_status'),
    ['ACTIVE', 'SUSPENDED', 'ARCHIVED'],
    'e_organization_status must contain exactly ACTIVE, SUSPENDED and ARCHIVED',
  );
  assert.deepEqual(
    await enumLabels(client, 'e_plan_tier'),
    ['BASIC', 'STANDARD', 'PREMIUM', 'ENTERPRISE'],
    'e_plan_tier must contain exactly BASIC, STANDARD, PREMIUM and ENTERPRISE',
  );

  const columns = await client.query(
    `SELECT column_name, data_type, udt_name, is_nullable, column_default
       FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'organizations'
        AND column_name = ANY($1::text[])`,
    [['status', 'plan_tier', 'branding_overrides']],
  );
  const byName = Object.fromEntries(columns.rows.map((row) => [row.column_name, row]));
  assert.equal(byName.status && byName.status.udt_name, 'e_organization_status', 'organizations.status type');
  assert.equal(byName.status && byName.status.is_nullable, 'NO', 'organizations.status must be NOT NULL');
  assert.match((byName.status && byName.status.column_default) || '', /ACTIVE/, 'organizations.status default');
  assert.equal(byName.plan_tier && byName.plan_tier.udt_name, 'e_plan_tier', 'organizations.plan_tier type');
  assert.equal(byName.plan_tier && byName.plan_tier.is_nullable, 'NO', 'organizations.plan_tier must be NOT NULL');
  assert.match((byName.plan_tier && byName.plan_tier.column_default) || '', /BASIC/, 'organizations.plan_tier default');
  assert.equal(byName.branding_overrides && byName.branding_overrides.data_type, 'jsonb', 'organizations.branding_overrides type');
  assert.equal(byName.branding_overrides && byName.branding_overrides.is_nullable, 'YES', 'organizations.branding_overrides must be nullable');
  assert.equal(byName.branding_overrides && byName.branding_overrides.column_default, null, 'organizations.branding_overrides must have no default');

  const inconsistent = await client.query(
    `SELECT count(*)::int AS count
       FROM public.organizations
      WHERE (is_active IS DISTINCT FROM FALSE AND status <> 'ACTIVE')
         OR (is_active = FALSE AND status <> 'SUSPENDED')`,
  );
  assert.equal(inconsistent.rows[0].count, 0, 'status must be consistent with the legacy is_active flag');

  const asopogua = await client.query(
    `SELECT id, status FROM public.organizations WHERE slug = 'asopogua'`,
  );
  assert.equal(asopogua.rowCount, 1, 'ASOPOGUA must exist');
  assert.equal(asopogua.rows[0].status, 'ACTIVE', 'ASOPOGUA must be ACTIVE');

  await client.query('BEGIN');
  try {
    await expectSqlState(
      client,
      `SELECT 'BOGUS'::public.e_organization_status`,
      [],
      '22P02',
      'invalid organization status label',
    );
    await expectSqlState(
      client,
      `SELECT 'free'::public.e_plan_tier`,
      [],
      '22P02',
      'invalid plan tier label',
    );
    await expectSqlState(
      client,
      `UPDATE public.organizations SET branding_overrides = '[1,2]'::jsonb WHERE id = $1`,
      [asopogua.rows[0].id],
      '23514',
      'non-object branding_overrides',
    );
    await client.query(
      `UPDATE public.organizations SET branding_overrides = $1::jsonb WHERE id = $2`,
      ['{"primaryColor":"#123456"}', asopogua.rows[0].id],
    );
  } finally {
    await client.query('ROLLBACK');
  }
}

module.exports = { runMigration029Checks };
