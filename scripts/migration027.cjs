const { Client } = require('pg');
const { runMigration027Checks } = require('../supabase/tests/027_platform_role.cjs');

async function main() {
  if (process.env.SIGHA_DB_ENV !== 'development' || process.env.NODE_ENV === 'production') {
    throw new Error('Set SIGHA_DB_ENV=development before running migration 027 checks.');
  }
  if (!process.env.SIGHA_DEV_DATABASE_URL) {
    throw new Error('SIGHA_DEV_DATABASE_URL is required; the test does not read or print repository secrets.');
  }

  const client = new Client({
    connectionString: process.env.SIGHA_DEV_DATABASE_URL,
    ssl: { rejectUnauthorized: false },
    connectionTimeoutMillis: 10000,
    application_name: 'sigha-db-migration027-test',
  });

  try {
    await client.connect();
    await runMigration027Checks(client);
    process.stdout.write('Migration 027 checks passed; no rows were modified.\n');
  } finally {
    await client.end();
  }
}

main().catch((error) => {
  const code = error && error.code ? ` (SQLSTATE ${error.code})` : '';
  process.stderr.write(`Migration 027 checks failed${code}: ${error instanceof Error ? error.message : 'unknown error'}\n`);
  process.exitCode = 1;
});
