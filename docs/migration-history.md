# Migration history

> Order of execution for the SQL files in this repo. After ÉPICA 2 (Supabase/Postgres), this is replaced by numbered `supabase/migrations/00X_*.sql`.
>
> Today: run `scriptDBCompleta.sql` as a single file. The other files are auxiliary.

---

## Current order (MySQL — development)

1. **`scriptDBCompleta.sql`** — main schema (~30 tables). Drops and recreates the `hogar_de_ancianos` database.
2. **`sp-auditoria.sql`** — adds the `sp_log_audit` procedure.
3. **`update_audit_reports.sql`** — incremental update to `audit_reports` (apply only if you already have a base schema without these columns).
4. **`data-usuario-auditoria-test.sql`** — optional: inserts a test user for the audit module.
5. **`clean_all_data.sql`** — dev only: `TRUNCATE`s all tables (does NOT drop them).

```bash
# Fresh setup
mysql -u root -p < scriptDBCompleta.sql
mysql -u root -p < sp-auditoria.sql
# (optional) mysql -u root -p < data-usuario-auditoria-test.sql

# Reset data (keep schema)
mysql -u root -p < clean_all_data.sql
```

> Or via Docker Compose: `cd sigha-api/docker && docker compose up -d` (boots MySQL with the schema preloaded).

---

## Target order (Supabase/Postgres — ÉPICA 2 ✅)

✅ **DONE 2026-06-10.** After migration, the SQL is split into ordered files under `supabase/migrations/`:

| File | Purpose | Status |
|---|---|---|
| `001_extensions_and_types.sql` | Enable `pgcrypto`, `citext`; create ENUM types | ✅ |
| `002_core_auth.sql` | `roles`, `users`, `user_two_factor`, `user_sessions`, `login_attempts`, `password_reset_tokens`, `email_verification_tokens`, `role_changes` | ✅ |
| `003_access_and_audit.sql` | `entrances_exits`, `digital_record`, `audit_reports`, `notifications`, `notification_attachment` | ✅ |
| `004_programs.sql` | `programs`, `sub_programs` (+ seeds) | ✅ |
| `005_virtual_records.sql` | `older_adult_family`, `older_adult`, `older_adult_subprogram`, `emergency_contacts`, `older_adult_updates`, `clinical_conditions`, `vaccines`, `clinical_history`, `clinical_history_and_conditions`, `vaccines_and_clinical_history`, `clinical_medication` | ✅ |
| `006_nursing_and_appointments.sql` | `specialized_area`, `specialized_appointment`, `nursing_records`, `physiotherapy_sessions`, `psychology_sessions`, `social_work_reports`, `medical_record` | ✅ |
| `007_functions.sql` | `clean_expired_sessions()`, `clean_expired_tokens()`, `get_failed_login_stats()`, `log_audit()`, `set_updated_at()` trigger | ✅ |
| `008_permissions.sql` | `permissions`, `role_permissions` (RBAC catalogue + per-role seeds) | ✅ |
| `009_virtual_file_procedures.sql` | `create_virtual_file()`, `delete_virtual_file()`, `get_virtual_file()`, `compute_audit_session_duration()` — ports of the legacy MySQL `CreateVirtualFile` / `DeleteVirtualFile` / `GetVirtualFile` / `sp_log_audit` (logout branch) procedures | ✅ |
| `seeds/000_seed_roles.sql` | Seeds the 8 default roles | ✅ |

Apply with the Supabase CLI:

```bash
supabase db push
```

Or paste each file into the Supabase SQL editor in order. See `supabase/README.md` for the full how-to.

---

## Change log

| Date | File | Change |
|---|---|---|
| (initial) | `scriptDBCompleta.sql` | Created |
| (incremental) | `update_audit_reports.sql` | Added columns/indices to `audit_reports` |
| (test) | `data-usuario-auditoria-test.sql` | Test fixture for audit module |
| (dev) | `clean_all_data.sql` | TRUNCATE all tables |
| (legacy) | `sp-auditoria.sql` | Audit stored procedure |

---

## Conventions for new migrations

- One logical change per file.
- Filename: `update_<table>_<short-desc>.sql` for ad-hoc updates; `NNN_<short-desc>.sql` for the numbered scheme.
- **Never drop a column without a backup plan.** Add the new column, backfill, then drop in a follow-up migration.
- **Never rename a column without also updating the backend entity in the same commit.**
- Always update `docs/tables-catalog.md` and `docs/er-diagram.md`.
- For Postgres, always include the reverse direction in the same file (`CREATE TABLE ... ; ... DROP TABLE ... ;`) so migrations are idempotent in dev.

---

## Forbidden

- ❌ Editing `scriptDBCompleta.sql` to add tables — once split, use `update_*.sql` or the numbered migrations.
- ❌ Using `pogrestsql/` (Notifuse Postgres dump) as a schema source.
- ❌ Direct schema changes against production (always via a migration file + review).
- ❌ Dropping the database in a shared/staging environment.
