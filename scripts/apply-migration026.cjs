const fs = require('node:fs');
const path = require('node:path');
const { Client } = require('pg');

const migrationPath = path.resolve(
  __dirname,
  '..',
  'supabase',
  'migrations',
  '026_clinical_integrity_tenancy_and_care.sql',
);

async function main() {
  if (process.env.SIGHA_DB_ENV !== 'development' || process.env.NODE_ENV === 'production') {
    throw new Error('Set SIGHA_DB_ENV=development before applying migration 026.');
  }
  const connectionString = process.env.SIGHA_DEV_DATABASE_URL;
  if (!connectionString) {
    throw new Error('SIGHA_DEV_DATABASE_URL is required.');
  }

  const target = new URL(connectionString);
  if (!/\.supabase\.com$/i.test(target.hostname)) {
    throw new Error('Migration 026 may only run against the configured Supabase development database.');
  }

  const client = new Client({
    connectionString,
    ssl: { rejectUnauthorized: false },
    connectionTimeoutMillis: 10000,
    application_name: 'sigha-db-migration026-apply',
  });

  try {
    await client.connect();
    const occupancyConflicts = await client.query(
      `SELECT id_room, bed_label, count(*)::int AS assignment_count,
              array_agg(jsonb_build_object(
                'assignmentId', id,
                'residentId', id_older_adult,
                'assignedAt', assigned_at,
                'dischargedAt', discharged_at
              ) ORDER BY assigned_at DESC, id DESC) AS assignments
         FROM public.patient_bed_assignments
        WHERE is_current = TRUE
        GROUP BY id_room, bed_label
       HAVING count(DISTINCT id_older_adult) > 1
        ORDER BY id_room, bed_label`,
    );
    if (occupancyConflicts.rowCount > 0) {
      process.stdout.write(`Active bed-assignment conflicts: ${occupancyConflicts.rowCount}\n`);
      for (const conflict of occupancyConflicts.rows) {
        process.stdout.write(
          `room=${conflict.id_room} bed=${conflict.bed_label} assignments=${JSON.stringify(conflict.assignments)}\n`,
        );
      }
      throw new Error('Resolve active bed assignments before applying migration 026.');
    }

    const existingTrigger = await client.query(
      `SELECT EXISTS (
         SELECT 1 FROM pg_trigger
          WHERE tgrelid = 'public.clinical_encounters'::regclass
            AND tgname = 'trg_prevent_signed_encounter_mutation'
            AND NOT tgisinternal
       ) AS applied`,
    );
    if (existingTrigger.rows[0].applied) {
      throw new Error('Migration 026 immutability trigger already exists; refusing to reapply.');
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

    process.stdout.write('Migration 026 applied to the configured development database.\n');
  } finally {
    await client.end();
  }
}

main().catch((error) => {
  const code = error && error.code ? ` (SQLSTATE ${error.code})` : '';
  process.stderr.write(`Migration 026 application failed${code}: ${error instanceof Error ? error.message : 'unknown error'}\n`);
  process.exitCode = 1;
});
