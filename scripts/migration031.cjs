const assert = require('node:assert/strict');
const { Client } = require('pg');

async function main() {
  if (process.env.SIGHA_DB_ENV !== 'development' || process.env.NODE_ENV === 'production') {
    throw new Error('Set SIGHA_DB_ENV=development to test migration 031.');
  }
  const connectionString = process.env.SIGHA_DEV_DATABASE_URL;
  if (!connectionString) throw new Error('SIGHA_DEV_DATABASE_URL is required.');
  const target = new URL(connectionString);
  if (!/\.supabase\.com$/i.test(target.hostname)) {
    throw new Error('Migration 031 tests may only query the configured Supabase development database.');
  }

  const client = new Client({
    connectionString,
    ssl: { rejectUnauthorized: false },
    connectionTimeoutMillis: 10000,
    application_name: 'sigha-db-migration031-test',
  });
  try {
    await client.connect();
    const prerequisites = await client.query(
      `SELECT EXISTS (
         SELECT 1 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'organization_members'
            AND column_name = 'role_id' AND is_nullable = 'NO'
       ) AS migration_030_applied`,
    );
    assert.equal(prerequisites.rows[0]?.migration_030_applied, true, 'migration 030 must be applied first');

    const column = await client.query(
      `SELECT data_type, character_maximum_length
         FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'permissions' AND column_name = 'p_module'`,
    );
    assert.equal(column.rows[0]?.data_type, 'character varying');
    assert.equal(Number(column.rows[0]?.character_maximum_length), 32);

    const permissions = await client.query(
      `SELECT p_module, p_action, count(*)::int AS assignments
         FROM public.permissions p
         LEFT JOIN public.role_permissions rp ON rp.permission_id = p.id AND rp.rp_granted = TRUE
        WHERE p.p_module IN ('carePlans','accessLogs','systemAudit','beds','lifestyle')
        GROUP BY p.p_module, p.p_action`,
    );
    assert.equal(permissions.rowCount, 17, 'expected 17 granular module/action permissions');
    assert.ok(permissions.rows.every((row) => Number(row.assignments) >= 1));
    assert.equal(
      permissions.rows.filter((row) => row.p_module === 'systemAudit').map((row) => row.p_action).join(','),
      'view',
      'system audit must expose read-only permission',
    );

    const roleAccess = await client.query(
      `SELECT lower(trim(r.r_name)) AS role_name, p.p_module, p.p_action, rp.rp_granted
         FROM public.role_permissions rp
         JOIN public.roles r ON r.id = rp.role_id
         JOIN public.permissions p ON p.id = rp.permission_id
        WHERE lower(trim(r.r_name)) IN ('super admin','admin','director','nurse','physiotherapist','psychologist','social worker')
          AND p.p_module IN ('carePlans','accessLogs','systemAudit','beds','lifestyle')`,
    );
    assert.ok(roleAccess.rows.some((row) => row.role_name === 'director' && row.p_module === 'systemAudit' && row.p_action === 'view' && row.rp_granted));
    assert.ok(roleAccess.rows.every((row) => row.p_module !== 'systemAudit' || row.p_action === 'view'));
    process.stdout.write('Migration 031 permission catalogue and role grants: PASS\n');
  } finally {
    await client.end();
  }
}

main().catch((error) => {
  const code = error && error.code ? ` (SQLSTATE ${error.code})` : '';
  process.stderr.write(`Migration 031 test failed${code}: ${error instanceof Error ? error.message : 'unknown error'}\n`);
  process.exitCode = 1;
});
