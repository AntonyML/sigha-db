const fs = require('node:fs');
const path = require('node:path');
const { Client } = require('pg');

const migrationPath = path.resolve(__dirname, '..', 'supabase', 'migrations', '032_fix_create_tenant_user_membership_role.sql');

async function main() {
  if (process.env.SIGHA_DB_ENV !== 'development' || process.env.NODE_ENV === 'production') {
    throw new Error('Set SIGHA_DB_ENV=development before applying migration 032.');
  }
  const connectionString = process.env.SIGHA_DEV_DATABASE_URL;
  if (!connectionString) throw new Error('SIGHA_DEV_DATABASE_URL is required.');
  const target = new URL(connectionString);
  if (!/\.supabase\.com$/i.test(target.hostname)) {
    throw new Error('Migration 032 may only run against the configured Supabase development database.');
  }

  const client = new Client({
    connectionString,
    ssl: { rejectUnauthorized: false },
    connectionTimeoutMillis: 10000,
    application_name: 'sigha-db-migration032-apply',
  });
  try {
    await client.connect();
    const prerequisites = await client.query(
      `SELECT EXISTS (
         SELECT 1 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'organization_members'
            AND column_name = 'role_id' AND is_nullable = 'NO'
       ) AS migration_030_applied,
       (SELECT count(*)::int FROM public.roles WHERE lower(trim(r_name)) = 'not specified') AS default_role_count`,
    );
    if (!prerequisites.rows[0].migration_030_applied) {
      throw new Error('Migration 030 must be applied before migration 032.');
    }
    if (prerequisites.rows[0].default_role_count !== 1) {
      throw new Error('The organization role "not specified" must exist exactly once.');
    }

    const currentFunction = await client.query(
      `SELECT p.prosrc
         FROM pg_proc p
         JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'create_tenant_user'
          AND p.oid = 'public.create_tenant_user(text,text,text,text,text,text)'::regprocedure`,
    );
    if (currentFunction.rows[0]?.prosrc && /organization_members\s*\(\s*user_id\s*,\s*organization_id\s*,\s*role_id\s*,\s*is_primary\s*\)/i.test(currentFunction.rows[0].prosrc)) {
      throw new Error('Migration 032 appears already applied; refusing to reapply.');
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
    process.stdout.write('Migration 032 applied to the configured development database.\n');
  } finally {
    await client.end();
  }
}

main().catch((error) => {
  const code = error && error.code ? ` (SQLSTATE ${error.code})` : '';
  process.stderr.write(`Migration 032 application failed${code}: ${error instanceof Error ? error.message : 'unknown error'}\n`);
  process.exitCode = 1;
});
