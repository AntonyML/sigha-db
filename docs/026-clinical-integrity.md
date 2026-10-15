# Migration 026: clinical integrity and tenant isolation

Migration `026_clinical_integrity_tenancy_and_care.sql` is a forward-only correction after migrations 001–025. It leaves applied migrations 021–025 unchanged and assigns existing development records to ASOPOGUA where they have no tenant.

The migration forces row-level security on resident, clinical, medication, nursing, residence, lifestyle, program, access, notification, memo, and audit data. Each request must set `app.current_tenant_id`; inserts without that context fail closed. The `sigha_app` role is non-login, non-superuser, cannot bypass RLS, and does not inherit privileges. The migration grants it to the database role that applies the migration so that role can switch to `sigha_app`.

Migration 025 added resident memos with a nullable tenant and acknowledgments without a tenant key. Migration 026 assigns unscoped memos to ASOPOGUA, derives acknowledgment tenant IDs from their parent memos, makes both tenant keys mandatory, and adds forced RLS and audit triggers. Composite foreign keys bind each memo to a resident, parent memo, and same-tenant author or recipient; acknowledgments bind to a same-tenant memo and member.

Signed encounters retain the SOAP columns from 022 and gain a SHA-256 signature hash and version. Historical signatures receive `legacy-unverified` with no invented hash. The PostgreSQL trigger `trg_prevent_signed_encounter_mutation` blocks changes and deletion of signed encounters; signed addenda receive the same protection. Historical specialty evaluations are linked to shared encounters and copied into `clinical_scale_evaluations`, preserving only answers that were actually recorded.

Medication rows with `status = 'scheduled'` and no administration timestamp are copied to `medication_administration_schedule_archive` and removed from the active event table. The active table rejects scheduled placeholders and enforces one event per tenant, prescription, and scheduled time. The API projects planned doses in memory and persists only actual administration actions.

The former room, stay, and lifestyle names remain security-invoker views for the current API entity mappings. New canonical tables model pavilions, beds, care programs, enrollments, resident access, and append-only tenant audit events. Shared catalogs remain global reference data with the permissions required by existing services.

## Verification on a development database

Apply this migration only to the Supabase development project after confirming that migrations 001–025 are present. Never use production credentials. Both scripts require an explicit development URL and refuse to run when `SIGHA_DB_ENV` is not `development`.

Set the variables in the current PowerShell session, apply the migration to development, then run the checks:

```powershell
$env:SIGHA_DB_ENV = 'development'
$env:SIGHA_DEV_DATABASE_URL = '<development database connection string>'
bun run apply:migration026
bun run test:migration026
Remove-Item Env:SIGHA_DEV_DATABASE_URL -ErrorAction SilentlyContinue
Remove-Item Env:SIGHA_DB_ENV -ErrorAction SilentlyContinue
```

The checks verify the restricted role, forced RLS on clinical and memo tables, the 022 immutability trigger, memo and acknowledgment tenant filtering, scheduled-placeholder archival, password-function access, and rejection of mutations to signed encounters and addenda. Test rows run in a transaction and are rolled back. PostgreSQL sequences may still advance during rollback, which only creates harmless gaps. The development database needs at least one ASOPOGUA resident and member for the clinical checks.
