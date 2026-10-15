const fs = require('node:fs');
const path = require('node:path');
const { Client } = require('pg');

const migrationPath = path.resolve(
  __dirname,
  '..',
  'supabase',
  'migrations',
  '029_organization_platform_fields.sql',
);

async function main() {
  if (process.env.SIGHA_DB_ENV !== 'development' || process.env.NODE_ENV === 'production') {
    throw new Error('Set SIGHA_DB_ENV=development before applying migration 029.');
  }
  const connectionString = process.env.SIGHA_DEV_DATABASE_URL;
  if (!connectionString) {
    throw new Error('SIGHA_DEV_DATABASE_URL is required.');
  }

  const target = new URL(connectionString);
  if (!/\.supabase\.com$/i.test(target.hostname)) {
    throw new Error('Migration 029 may only run against the configured Supabase development database.');
  }

  const client = new Client({
    connectionString,
    ssl: { rejectUnauthorized: false },
    connectionTimeoutMillis: 10000,
    application_name: 'sigha-db-migration029-apply',
  });

  try {
    await client.connect();
    const already = await client.query(
      `SELECT EXISTS (
         SELECT 1
           FROM pg_type t
           JOIN pg_namespace n ON n.oid = t.typnamespace
          WHERE t.typname = 'e_organization_status'
            AND n.nspname = 'public'
       ) AS applied`,
    );
    if (already.rows[0].applied) {
      throw new Error('Migration 029 appears already applied; refusing to reapply.');
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

    process.stdout.write('Migration 029 applied to the configured development database.\n');
  } finally {
    await client.end();
  }
}

main().catch((error) => {
  const code = error && error.code ? ` (SQLSTATE ${error.code})` : '';
  process.stderr.write(`Migration 029 application failed${code}: ${error instanceof Error ? error.message : 'unknown error'}\n`);
  process.exitCode = 1;
});
