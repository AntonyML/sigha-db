# AGENTS.md — Database (`sigha-db/`)

> **You are an AI agent working on the MySQL database (and soon Supabase/Postgres) of the Hogar de Ancianos platform.**
> Read the root `AGENTS.md` first, then this file.

---

## 0. Scope and authority

- **You work only inside `E:\Dev\TCU\sigha-db\`.**
- **You do not edit** `backend/` entities, `frontend/`, or root files (except with explicit permission).
- **You do not push** to the remote. The user reviews and pushes.
- **You do not amend** published commits.
- **You do not** commit production data dumps (only structure, migrations, and seed data).

---

## 1. Stack

- **Engine:** MySQL 8 (today)
- **Target engine:** PostgreSQL 15+ via Supabase (ÉPICA 2)
- **Migrations:** Today — single `scriptDBCompleta.sql` + auxiliary `update_*.sql`. Future — numbered `migrations/001_*.sql` etc.
- **Audit:** `sp_log_audit` procedure (MySQL) — to be replaced by a Postgres function or moved to the backend's `AuditService`.

---

## 2. Folder map (this repo)

```
sigha-db/
├── AGENTS.md                                # this file
├── docs/                                    # AI-facing reference docs
│   ├── tables-catalog.md                    # every table
│   ├── er-diagram.md                        # relationships (textual)
│   └── migration-history.md                 # execution order + history
├── scriptDBCompleta.sql                     # main schema (~30 tables)
├── sp-auditoria.sql                         # audit procedure (legacy)
├── clean_all_data.sql                       # truncate for dev
├── data-usuario-auditoria-test.sql          # test fixtures (auditor user)
├── update_audit_reports.sql                 # incremental update
└── pogrestsql/                              # ⚠️ NOT a real migration; Postgres dump of Notifuse, do not use
```

---

## 3. Tables (~30)

The full list is in `docs/tables-catalog.md`. Highlights:

- **Auth:** `users`, `roles`, `user_two_factor`, `user_sessions`, `login_attempts`, `password_reset_tokens`, `email_verification_tokens`
- **Access:** `entrances_exits`
- **Roles audit:** `role_changes`
- **Older adults:** `older_adult`, `older_adult_family`, `older_adult_updates`, `older_adult_subprogram`
- **Clinical:** `clinical_history`, `clinical_conditions`, `clinical_medications`, `clinical_history_and_condition`, `vaccines`, `vaccines_and_clinical_history`
- **Programs:** `programs`, `sub_programs`
- **Nursing:** `nursing_records`, `specialized_appointments`, `specialized_areas`
- **Audit / logs:** `audit_reports`, `digital_records`, `notifications`, `notification_attachments`
- **Emergency contacts:** `emergency_contacts`

> The `medical_record` table is referenced by the backend (planned) but the actual CREATE TABLE is missing or pending — verify in `scriptDBCompleta.sql`.

---

## 4. Naming conventions

- **Tables:** snake_case, plural or plural-ish (`users`, `roles`, `nursing_records`, but `older_adult` is singular).
- **Columns:** snake_case. Legacy prefixes: `u_` (user), `r_` (role), `tfa_` (2FA), `rpt_` (report), `not_` (notification).
- **PKs:** `id` INT AUTO_INCREMENT.
- **FKs:** `<table>_id` (`user_id`, `role_id`).
- **Timestamps:** `create_at`, `update_at` (legacy spelling — keep).
- **Soft delete:** prefer `u_is_active` boolean over a `deletedAt` column.

---

## 5. Adding a new table — checklist

1. Add the `CREATE TABLE` block to `scriptDBCompleta.sql` (and, after ÉPICA 2, a new file under `supabase/migrations/`).
2. Add appropriate `CREATE INDEX` statements for FKs and frequent lookups.
3. Add the corresponding TypeORM entity in the backend (`src/ucr/ac/cr/ie/domain/<area>/<thing>.entity.ts`).
4. **Add the entity to `database.providers.ts`** (see `backend/docs/entities.md`).
5. Add a row to `docs/tables-catalog.md`.
6. Update `docs/er-diagram.md` if there are new relationships.
7. Commit: `feat(db): add <table> table`.

---

## 6. Modifying a table — checklist

1. **Do not drop columns** without an `ALTER TABLE ... DROP COLUMN` in a separate migration.
2. **Do not rename columns** without updating both the SQL and the backend entity in the same commit.
3. **Do not change ENUM values** without a migration that adds the new value first, then optionally removes the old one (MySQL allows adding ENUM values in place; removing requires a column recreate).
4. Add an `update_*.sql` file if the change applies to existing deployments.
5. Add a row to `docs/migration-history.md` describing the change.
6. Commit: `feat(db): add <column> to <table>` or `fix(db): ...`.

---

## 7. Migration order (target, Supabase)

After ÉPICA 2, the SQL will be split into ordered files under `supabase/migrations/`:

```
supabase/migrations/
  001_extensions_and_types.sql
  002_core_auth.sql
  003_virtual_records.sql
  004_nursing_and_appointments.sql
  005_access_and_audit.sql
  006_functions.sql
  007_seed_roles.sql
```

Until then, the canonical schema is `scriptDBCompleta.sql` (run as a single script).

---

## 8. Common queries (for AI agents)

### 8.1 List all tables

```sql
SELECT TABLE_NAME, TABLE_ROWS
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'hogar_de_ancianos'
ORDER BY TABLE_NAME;
```

### 8.2 List columns of a table

```sql
SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_KEY, COLUMN_DEFAULT, EXTRA
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = 'hogar_de_ancianos' AND TABLE_NAME = 'users'
ORDER BY ORDINAL_POSITION;
```

### 8.3 List foreign keys of a table

```sql
SELECT
  CONSTRAINT_NAME,
  COLUMN_NAME,
  REFERENCED_TABLE_NAME,
  REFERENCED_COLUMN_NAME
FROM information_schema.KEY_COLUMN_USAGE
WHERE TABLE_SCHEMA = 'hogar_de_ancianos'
  AND TABLE_NAME = 'users'
  AND REFERENCED_TABLE_NAME IS NOT NULL;
```

### 8.4 Find orphaned rows (broken FKs — should be zero)

```sql
SELECT u.id, u.role_id
FROM users u
LEFT JOIN roles r ON r.id = u.role_id
WHERE r.id IS NULL AND u.role_id IS NOT NULL;
```

---

## 9. MySQL → Postgres conversion cheat sheet (for ÉPICA 2)

See `TareasPendientes.md` §ÉPICA 2 and `.opencode/skills/epic-supabase/SKILL.md` for the full guide.

| MySQL | Postgres |
|---|---|
| `AUTO_INCREMENT` | `GENERATED BY DEFAULT AS IDENTITY` or `SERIAL` |
| `ENUM('a','b')` | `CREATE TYPE ... AS ENUM (...)` or `TEXT` + `CHECK` |
| `` `backticks` `` | `"quoted"` or unquoted |
| `DATETIME` | `TIMESTAMPTZ` |
| `BOOLEAN DEFAULT FALSE` | Compatible |
| `DELIMITER $$ ... PROCEDURE` | `CREATE OR REPLACE FUNCTION ... RETURNS void LANGUAGE plpgsql` |
| `ON UPDATE CURRENT_TIMESTAMP` | Trigger `BEFORE UPDATE` or app-level |

---

## 10. Documentation in this repo

| File | Purpose |
|---|---|
| `AGENTS.md` | This file |
| `docs/tables-catalog.md` | Every table in the schema |
| `docs/er-diagram.md` | Relationships (textual) |
| `docs/migration-history.md` | Execution order + change history |
| `scriptDBCompleta.sql` | Main schema (canonical today) |
| `sp-auditoria.sql` | Audit procedure |
| `clean_all_data.sql` | Dev reset (TRUNCATE all tables) |
| `data-usuario-auditoria-test.sql` | Test fixtures |
| `update_audit_reports.sql` | Incremental update for `audit_reports` |
| `pogrestsql/` | ⚠️ Notifuse Postgres dump — DO NOT use as a migration source |

---

## 11. Escalating to the coordinator

If a task requires changing a backend entity, an API contract, or a frontend service in lockstep, **stop and tell the user**, or invoke the `fullstack-coordinator` agent from the root `.opencode/agents/`.
