const assert = require('node:assert/strict');

async function runMigration033Checks(client) {
  const colPriv = await client.query(
    `SELECT has_column_privilege('sigha_app', 'public.users', 'platform_role', 'SELECT') AS can_select_platform_role`,
  );
  assert.equal(
    colPriv.rows[0]?.can_select_platform_role,
    true,
    'sigha_app must have SELECT privilege on public.users.platform_role',
  );

  const sharedTables = [
    'roles',
    'permissions',
    'role_permissions',
    'clinical_conditions',
    'vaccines',
    'specialized_area',
    'medication_catalog',
    'icd10_catalog',
    'system_settings',
  ];

  const policies = await client.query(
    `SELECT tablename, policyname
       FROM pg_policies
      WHERE schemaname = 'public'
        AND policyname = 'shared_catalog_sigha_app_policy'
        AND tablename = ANY($1::text[])`,
    [sharedTables],
  );
  assert.equal(
    policies.rowCount,
    sharedTables.length,
    'every shared reference table must have shared_catalog_sigha_app_policy',
  );

  const organization = await client.query(
    `SELECT id FROM public.organizations WHERE slug = 'asopogua' AND is_active = TRUE`,
  );
  assert.equal(organization.rowCount, 1, 'an active ASOPOGUA development tenant must exist');

  const actor = await client.query(
    `SELECT user_id, role_id FROM public.organization_members
      WHERE organization_id = $1 ORDER BY user_id LIMIT 1`,
    [organization.rows[0].id],
  );
  assert.equal(actor.rowCount, 1, 'the development tenant must have at least one member');

  await client.query('BEGIN');
  try {
    await client.query('SET LOCAL ROLE sigha_app');
    await client.query(
      `SELECT set_config('app.current_tenant_id', $1, true), set_config('app.current_user_id', $2, true)`,
      [String(organization.rows[0].id), String(actor.rows[0].user_id)],
    );

    const roleCheck = await client.query(
      `SELECT id, r_name FROM public.roles WHERE id = $1`,
      [actor.rows[0].role_id],
    );
    assert.equal(roleCheck.rowCount, 1, 'sigha_app must be able to read active membership role from public.roles');

    const rolePermCheck = await client.query(
      `SELECT count(*)::int AS cnt
         FROM public.role_permissions rp
         JOIN public.permissions p ON p.id = rp.permission_id
        WHERE rp.role_id = $1`,
      [actor.rows[0].role_id],
    );
    assert.ok(
      Number(rolePermCheck.rows[0]?.cnt) > 0,
      'sigha_app must be able to read role permissions for the active membership role',
    );

    const userPlatformRoleCheck = await client.query(
      `SELECT id, platform_role FROM public.users WHERE id = $1`,
      [actor.rows[0].user_id],
    );
    assert.equal(
      userPlatformRoleCheck.rowCount,
      1,
      'sigha_app must be able to select platform_role from public.users for tenant members',
    );
  } finally {
    await client.query('ROLLBACK');
  }
}

module.exports = { runMigration033Checks };
