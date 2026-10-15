const fs = require('node:fs');
const path = require('node:path');
const { Client } = require('pg');

const migrationPath = path.resolve(__dirname, '..', 'supabase', 'migrations', '031_module_permissions.sql');

async function main() {
  if (process.env.SIGHA_DB_ENV !== 'development' || process.env.NODE_ENV === 'production') {
    throw new Error('Set SIGHA_DB_ENV=development before applying migration 031.');
  }
  const connectionString = process.env.SIGHA_DEV_DATABASE_URL;
  if (!connectionString) throw new Error('SIGHA_DEV_DATABASE_URL is required.');

  const target = new URL(connectionString);
  if (!/\.supabase\.com$/i.test(target.hostname)) {
    throw new Error('Migration 031 may only run against the configured Supabase development database.');
  }

  const client = new Client({
    connectionString,
    ssl: { rejectUnauthorized: false },
    connectionTimeoutMillis: 10000,
    application_name: 'sigha-db-migration031-apply',
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
    if (!prerequisites.rows[0].migration_030_applied) {
      throw new Error('Migration 030 must be integrated and applied before migration 031.');
    }

    const alreadyApplied = await client.query(
      `SELECT EXISTS (
         SELECT 1 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'permissions'
            AND column_name = 'p_module' AND data_type = 'character varying'
       ) AND EXISTS (
         SELECT 1 FROM public.permissions WHERE p_module::TEXT = 'carePlans'
       ) AS applied`,
    );
    if (alreadyApplied.rows[0].applied) {
      throw new Error('Migration 031 module permissions are already present; refusing to reapply.');
    }

    const sql = fs.readFileSync(migrationPath, 'utf8');
    await client.query('BEGIN');
    try {
      await client.query(sql);
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    }
    process.stdout.write('Migration 031 applied to the configured development database.\n');
  } finally {
    await client.end();
  }
}

main().catch((error) => {
  const code = error && error.code ? ` (SQLSTATE ${error.code})` : '';
  process.stderr.write(`Migration 031 application failed${code}: ${error instanceof Error ? error.message : 'unknown error'}\n`);
  process.exitCode = 1;
});
