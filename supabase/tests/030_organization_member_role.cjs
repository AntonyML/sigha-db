const assert = require('node:assert/strict');

async function expectSqlState(client, sql, expectedCode, label) {
  await client.query('SAVEPOINT migration030_expected_error');
  let caught;
  try {
    await client.query(sql);
  } catch (error) {
    caught = error;
  }
  await client.query('ROLLBACK TO SAVEPOINT migration030_expected_error');
  await client.query('RELEASE SAVEPOINT migration030_expected_error');
  assert.equal(caught && caught.code, expectedCode, `${label} must fail with SQLSTATE ${expectedCode}`);
}

async function runMigration030Checks(client) {
  const column = await client.query(
    `SELECT data_type, is_nullable
       FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'organization_members'
        AND column_name = 'role_id'`,
  );
  assert.equal(column.rowCount, 1, 'organization_members.role_id must exist');
  assert.equal(column.rows[0].data_type, 'integer', 'organization_members.role_id type');
  assert.equal(column.rows[0].is_nullable, 'NO', 'organization_members.role_id must be NOT NULL');

  const fk = await client.query(
    `SELECT pg_get_constraintdef(oid) AS def
       FROM pg_constraint
      WHERE conname = 'fk_organization_members_role'`,
  );
  assert.equal(fk.rowCount, 1, 'fk_organization_members_role must exist');
  assert.match(fk.rows[0].def, /REFERENCES roles\(id\)/, 'membership role must reference roles(id)');

  const superAdmin = await client.query(
    `SELECT count(*)::int AS c FROM public.roles WHERE id = 1 OR r_name = 'super admin'`,
  );
  assert.equal(superAdmin.rows[0].c, 0, 'the super admin role must be removed from the catalog');
  const admin = await client.query(
    `SELECT count(*)::int AS c FROM public.roles WHERE id = 2 AND r_name = 'admin'`,
  );
  assert.equal(admin.rows[0].c, 1, 'the admin role must remain in the catalog');

  const nullRoles = await client.query(
    `SELECT count(*)::int AS c FROM public.organization_members WHERE role_id IS NULL`,
  );
  assert.equal(nullRoles.rows[0].c, 0, 'no membership may have a NULL role_id');
  const orphans = await client.query(
    `SELECT count(*)::int AS c
       FROM public.organization_members AS m
       LEFT JOIN public.roles AS r ON r.id = m.role_id
      WHERE r.id IS NULL`,
  );
  assert.equal(orphans.rows[0].c, 0, 'every membership role_id must reference an existing role');

  const ownersNotAdmin = await client.query(
    `SELECT count(*)::int AS c
       FROM public.organization_members AS m
       JOIN public.users AS u ON u.id = m.user_id
      WHERE u.platform_role = 'PLATFORM_OWNER'
        AND m.role_id <> 2`,
  );
  assert.equal(ownersNotAdmin.rows[0].c, 0, 'platform owners must hold an admin organization role');

  const owners = await client.query(
    `SELECT count(*)::int AS c FROM public.users WHERE platform_role = 'PLATFORM_OWNER'`,
  );
  const adminMemberships = await client.query(
    `SELECT count(*)::int AS c FROM public.organization_members WHERE role_id = 2`,
  );
  assert.ok(owners.rows[0].c >= 1, 'at least one platform owner is expected after the backfill');
  assert.equal(
    adminMemberships.rows[0].c,
    owners.rows[0].c,
    'admin memberships must match the promoted platform owners',
  );

  const wrongDefault = await client.query(
    `SELECT count(*)::int AS c
       FROM public.organization_members AS m
       JOIN public.users AS u ON u.id = m.user_id
      WHERE u.role_id IS NULL
        AND u.platform_role IS NULL
        AND m.role_id <> 8`,
  );
  assert.equal(wrongDefault.rows[0].c, 0, 'members without a legacy or platform role must default to not specified');

  await client.query('BEGIN');
  try {
    await expectSqlState(
      client,
      `UPDATE public.organization_members SET role_id = 1 WHERE role_id IS NOT NULL`,
      '23503',
      'membership role must reference an existing role',
    );
    await expectSqlState(
      client,
      `UPDATE public.organization_members SET role_id = NULL WHERE role_id IS NOT NULL`,
      '23502',
      'membership role must be NOT NULL',
    );
  } finally {
    await client.query('ROLLBACK');
  }
}

module.exports = { runMigration030Checks };
