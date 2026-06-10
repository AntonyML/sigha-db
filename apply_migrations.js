/**
 * apply_migrations.js
 * Aplica las migraciones Supabase (001-007) + seed de roles.
 * Usar desde E:\Dev\TCU con: node sigha-db/apply_migrations.js
 *
 * Requiere: node_modules/pg instalado en sigha-api.
 * Lee DATABASE_URL de sigha-api/.env automáticamente.
 */

const path = require('path');
const fs   = require('fs');

// ---- leer .env de sigha-api ----
const envPath = path.join(__dirname, '..', 'sigha-api', '.env');
const envContent = fs.readFileSync(envPath, 'utf8');
const envVars = {};
for (const line of envContent.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const idx = trimmed.indexOf('=');
    if (idx === -1) continue;
    const key = trimmed.slice(0, idx).trim();
    const val = trimmed.slice(idx + 1).trim();
    envVars[key] = val;
}

const DATABASE_URL = envVars['DATABASE_URL'];
const DB_SSL       = envVars['DB_SSL'] === 'true';

if (!DATABASE_URL || DATABASE_URL === 'FILL_ME') {
    console.error('ERROR: DATABASE_URL no está configurada en sigha-api/.env');
    process.exit(1);
}

// ---- cargar pg desde sigha-api/node_modules ----
const pgPath = path.join(__dirname, '..', 'sigha-api', 'node_modules', 'pg');
const { Client } = require(pgPath);

const migrations = [
    'supabase/migrations/001_extensions_and_types.sql',
    'supabase/migrations/002_core_auth.sql',
    'supabase/migrations/003_access_and_audit.sql',
    'supabase/migrations/004_programs.sql',
    'supabase/migrations/005_virtual_records.sql',
    'supabase/migrations/006_nursing_and_appointments.sql',
    'supabase/migrations/007_functions.sql',
    'supabase/seeds/000_seed_roles.sql',
];

async function run() {
    const client = new Client({
        connectionString: DATABASE_URL,
        ssl: DB_SSL ? { rejectUnauthorized: false } : false,
    });

    console.log('Conectando a Supabase...');
    await client.connect();
    console.log('Conexión OK.\n');

    for (const rel of migrations) {
        const fullPath = path.join(__dirname, rel);
        if (!fs.existsSync(fullPath)) {
            console.warn(`  SKIP (no existe): ${rel}`);
            continue;
        }
        const sql = fs.readFileSync(fullPath, 'utf8');
        process.stdout.write(`  Aplicando ${rel} ... `);
        try {
            await client.query(sql);
            console.log('OK');
        } catch (err) {
            // Errores de "already exists" son esperados en re-runs
            const msg = err.message || '';
            if (msg.includes('already exists') || msg.includes('duplicate')) {
                console.log(`SKIP (ya existe: ${msg.split('\n')[0]})`);
            } else {
                console.error(`\nERROR en ${rel}:\n${msg}`);
                await client.end();
                process.exit(1);
            }
        }
    }

    await client.end();
    console.log('\n=== Migraciones completadas. Base de datos lista. ===');
}

run().catch(err => {
    console.error('Error fatal:', err.message);
    process.exit(1);
});
