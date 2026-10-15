const assert = require('node:assert/strict');

async function runMigration032Checks(client) {
  const functionResult = await client.query(
    `SELECT p.prosrc,
            has_function_privilege('sigha_app', p.oid, 'EXECUTE') AS app_can_execute
       FROM pg_proc p
       JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.proname = 'create_tenant_user'
        AND p.oid = 'public.create_tenant_user(text,text,text,text,text,text)'::regprocedure`,
  );
  assert.equal(functionResult.rowCount, 1, 'create_tenant_user with the six-argument API contract must exist');
  assert.match(
    functionResult.rows[0].prosrc,
    /organization_members\s*\(\s*user_id\s*,\s*organization_id\s*,\s*role_id\s*,\s*is_primary\s*\)/i,
    'create_tenant_user must populate organization_members.role_id',
  );
  assert.equal(functionResult.rows[0].app_can_execute, true, 'sigha_app must retain function execute permission');

  const defaultRole = await client.query(
    `SELECT id FROM public.roles WHERE lower(trim(r_name)) = 'not specified'`,
  );
  assert.equal(defaultRole.rowCount, 1, 'the default organization role must exist exactly once');

  const organization = await client.query(
    `SELECT id FROM public.organizations WHERE slug = 'asopogua' AND is_active = TRUE`,
  );
  assert.equal(organization.rowCount, 1, 'an active ASOPOGUA development tenant must exist');
  const actor = await client.query(
    `SELECT user_id FROM public.organization_members
      WHERE organization_id = $1 ORDER BY user_id LIMIT 1`,
    [organization.rows[0].id],
  );
  assert.equal(actor.rowCount, 1, 'the development tenant must have a member to authorize user creation');

  const uniqueSuffix = `${Date.now()}${Math.floor(Math.random() * 10000)}`;
  await client.query('BEGIN');
  try {
    await client.query('SET LOCAL ROLE sigha_app');
    await client.query(
      `SELECT set_config('app.current_tenant_id',$1,true), set_config('app.current_user_id',$2,true)`,
      [String(organization.rows[0].id), String(actor.rows[0].user_id)],
    );
    const created = await client.query(
      `SELECT public.create_tenant_user($1,$2,$3,$4,$5,$6) AS id`,
      [
        `9${uniqueSuffix}`,
        'Migration',
        'Role',
        null,
        `migration032-${uniqueSuffix}@example.invalid`,
        'test-password-hash',
      ],
    );
    const membership = await client.query(
      `SELECT role_id FROM public.organization_members
        WHERE organization_id = $1 AND user_id = $2`,
      [organization.rows[0].id, created.rows[0].id],
    );
    assert.equal(membership.rowCount, 1, 'the new user must be a member of the active tenant');
    assert.equal(Number(membership.rows[0].role_id), Number(defaultRole.rows[0].id));
  } finally {
    await client.query('ROLLBACK');
  }
}

module.exports = { runMigration032Checks };
