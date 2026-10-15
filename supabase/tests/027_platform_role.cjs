const assert = require('node:assert/strict');

async function expectSqlState(client, sql, values, expectedCode, label) {
  await client.query('SAVEPOINT migration027_expected_error');
  let caught;
  try {
    await client.query(sql, values);
  } catch (error) {
    caught = error;
  }
  await client.query('ROLLBACK TO SAVEPOINT migration027_expected_error');
  await client.query('RELEASE SAVEPOINT migration027_expected_error');
  assert.equal(caught && caught.code, expectedCode, `${label} must fail with SQLSTATE ${expectedCode}`);
}

async function runMigration027Checks(client) {
  const enumLabels = await client.query(
    `SELECT e.enumlabel
       FROM pg_type t
       JOIN pg_namespace n ON n.oid = t.typnamespace
       JOIN pg_enum e ON e.enumtypid = t.oid
      WHERE n.nspname = 'public' AND t.typname = 'e_platform_role'
      ORDER BY e.enumsortorder`,
  );
  assert.deepEqual(
    enumLabels.rows.map((row) => row.enumlabel),
    ['PLATFORM_OWNER', 'PLATFORM_SUPPORT'],
    'e_platform_role must contain exactly PLATFORM_OWNER and PLATFORM_SUPPORT',
  );

  const column = await client.query(
    `SELECT udt_name, is_nullable, column_default
       FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'users'
        AND column_name = 'platform_role'`,
  );
  assert.equal(column.rowCount, 1, 'users.platform_role must exist');
  assert.equal(column.rows[0].udt_name, 'e_platform_role', 'platform_role must use the e_platform_role type');
  assert.equal(column.rows[0].is_nullable, 'YES', 'platform_role must be nullable');
  assert.equal(column.rows[0].column_default, null, 'platform_role must not have a default');

  const index = await client.query(
    `SELECT indexdef FROM pg_indexes
      WHERE schemaname = 'public'
        AND tablename = 'users'
        AND indexname = 'idx_users_platform_role'`,
  );
  assert.equal(index.rowCount, 1, 'idx_users_platform_role must exist');
  assert.match(index.rows[0].indexdef, /WHERE \(platform_role IS NOT NULL\)/i, 'the index must be partial on platform_role');

  const assigned = await client.query(
    `SELECT count(*)::int AS count FROM public.users WHERE platform_role IS NOT NULL`,
  );
  assert.equal(assigned.rows[0].count, 0, 'migration 027 must not assign any platform role');

  await client.query('BEGIN');
  try {
    await expectSqlState(
      client,
      `SELECT 'BOGUS'::public.e_platform_role`,
      [],
      '22P02',
      'invalid platform role label',
    );
    await expectSqlState(
      client,
      `SELECT 'platform_owner'::public.e_platform_role`,
      [],
      '22P02',
      'platform role labels must be upper-case',
    );
  } finally {
    await client.query('ROLLBACK');
  }
}

module.exports = { runMigration027Checks };
