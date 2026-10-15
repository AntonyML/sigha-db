const assert = require('node:assert/strict');
const { Client } = require('pg');
const { runMigration032Checks } = require('../supabase/tests/032_create_tenant_user_membership_role.cjs');

async function main() {
  if (process.env.SIGHA_DB_ENV !== 'development' || process.env.NODE_ENV === 'production') {
    throw new Error('Set SIGHA_DB_ENV=development to test migration 032.');
  }
  const connectionString = process.env.SIGHA_DEV_DATABASE_URL;
  if (!connectionString) throw new Error('SIGHA_DEV_DATABASE_URL is required.');
  const target = new URL(connectionString);
  if (!/\.supabase\.com$/i.test(target.hostname)) {
    throw new Error('Migration 032 tests may only query the configured Supabase development database.');
  }

  const client = new Client({
    connectionString,
    ssl: { rejectUnauthorized: false },
    connectionTimeoutMillis: 10000,
    application_name: 'sigha-db-migration032-test',
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
    await runMigration032Checks(client);
    process.stdout.write('Migration 032 user membership role checks passed; test rows were rolled back.\n');
  } finally {
    await client.end();
  }
}

main().catch((error) => {
  const code = error && error.code ? ` (SQLSTATE ${error.code})` : '';
  process.stderr.write(`Migration 032 test failed${code}: ${error instanceof Error ? error.message : 'unknown error'}\n`);
  process.exitCode = 1;
});
