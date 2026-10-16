const fs = require('node:fs');
const path = require('node:path');
const { Client } = require('pg');

const baselinePath = path.resolve(
  __dirname,
  '..',
  'supabase',
  'migrations',
  '001_baseline.sql',
);

async function main() {
  if (process.env.SIGHA_DB_ENV !== 'development' || process.env.NODE_ENV === 'production') {
    throw new Error('Set SIGHA_DB_ENV=development before applying baseline.');
  }
  const connectionString = process.env.SIGHA_DEV_DATABASE_URL;
  if (!connectionString) throw new Error('SIGHA_DEV_DATABASE_URL is required.');
  const target = new URL(connectionString);
  if (!/\.supabase\.com$/i.test(target.hostname)) {
    throw new Error('Baseline migration may only run against the configured Supabase development database.');
  }

  process.stdout.write(`Connecting to ${target.hostname}...\n`);
  const client = new Client({
    connectionString,
    ssl: { rejectUnauthorized: false },
    connectionTimeoutMillis: 15000,
    application_name: 'sigha-db-baseline-apply',
  });

  try {
    await client.connect();
    process.stdout.write('Reading 001_baseline.sql...\n');
    const sql = fs.readFileSync(baselinePath, 'utf8');

    process.stdout.write('Applying 001_baseline.sql (transactional execution)...\n');
    await client.query('BEGIN');
    try {
      await client.query(sql);
      await client.query('COMMIT');
      process.stdout.write('✓ 001_baseline.sql applied successfully to the development database.\n');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    }
  } finally {
    await client.end();
  }
}

main().catch((error) => {
  const code = error && error.code ? ` (SQLSTATE ${error.code})` : '';
  process.stderr.write(`Baseline application failed${code}: ${error instanceof Error ? error.message : 'unknown error'}\n`);
  if (error.detail) process.stderr.write(`Detail: ${error.detail}\n`);
  if (error.hint) process.stderr.write(`Hint: ${error.hint}\n`);
  if (error.where) process.stderr.write(`Where: ${error.where}\n`);
  process.exitCode = 1;
});
