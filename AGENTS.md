# AGENTS.md — Database (`sigha-db/`)

> **You are an AI agent working on the Supabase/Postgres database of the Hogar de Ancianos platform.**
> This file contains the database-specific rules and the shared Git workflow for this repository.

---

## 0. Scope and authority

- **Work only in the `sigha-db` repository.** Cross-repository work is assigned to a separate agent and worktree for each repository.
- **You do not push** to the remote. The user reviews and pushes.
- **You do not amend** published commits.
- **You do not** commit production data dumps (only structure, migrations, and seed data).

## Coordinación de agentes y Git

### Identidad y alcance

Al iniciar, identifica tu trabajo con: `Agente: <id/rol> | proyecto: sigha-db | rama: <rama> | worktree: <ruta> | archivos: <alcance>`. El coordinador asigna archivos y evita que dos agentes editen los mismos archivos. Para cambios de frontend, API y base de datos, asigna un agente y un worktree por repositorio; acuerden los contratos compartidos antes de trabajar en paralelo.

### Ramas y worktrees

- `dev` es la rama de integración. Cada agente trabaja en un worktree exclusivo y una rama única `agent/<id>/<tarea>`, creada desde `dev`; usa `~/worktrees/sigha-db/<id>-<tarea>` como ubicación del worktree.
- Si no existe `dev` local ni `origin/dev`, detén la creación de ramas y pide al mantenedor que establezca `dev` desde una base aprobada. `main` queda reservada: no hagas checkout, no bases ramas de tarea en ella ni la uses como destino de commit, merge o integración.
- No compartas worktrees, ramas ni sesiones de edición. Cada agente confirma cambios únicamente en su propia rama.
- Para analizar arquitectura, flujos o impacto, consulta CodeGraph antes de buscar archivos. Cada worktree necesita su propio `.codegraph/`; si falta, ejecuta `gentle-ai codegraph init --cwd <ruta-del-worktree>`. No copies ni compartas índices. Después de editar, deja sincronizar al watcher; usa `codegraph sync` solo si está apagado o el índice queda desactualizado.

### Operaciones Git y bloqueos

- El coordinador serializa por repositorio la creación o eliminación de worktrees y ramas, y toda integración o rebase sobre `dev`. Los agentes pueden implementar y verificar en paralelo en sus worktrees.
- Ejecuta como máximo un comando Git a la vez en cada worktree. Si Git informa que hay un lock, espera y localiza el proceso propietario; no borres archivos `.lock` mientras un proceso Git pueda estar activo.
- No hagas push ni amend de commits publicados; el usuario conserva la revisión y publicación remotas.

### Integración y registro

El agente entrega al coordinador el resumen, archivos modificados y verificaciones realizadas. El coordinador integra ramas completadas a `dev`, una por una y en orden de dependencias. Solo el coordinador actualiza `CHANGELOG.md` después de cada integración; los agentes entregan una nota lista para registrar, sin editar ese archivo.

Para cambios de esquema en paralelo, el coordinador reserva por adelantado un número de migración distinto para cada tarea. No reutilices un número asignado ni edites migraciones que ya se aplicaron.

---

## 1. Stack

- **Engine:** PostgreSQL 15+ via Supabase
- **Migrations:** Numbered `supabase/migrations/001_*.sql` through `012_*.sql`
- **Seeds:** `supabase/seeds/000_seed_roles.sql`
- **Audit:** Handled via backend's `AuditService` (TypeORM entity-based)

---

## 2. Folder map (this repo)

```
sigha-db/
├── AGENTS.md                                # this file
├── supabase/
│   ├── README.md                            # how to apply migrations
│   ├── migrations/
│   │   ├── 001_extensions_and_types.sql
│   │   ├── 002_core_auth.sql
│   │   ├── 003_access_and_audit.sql
│   │   ├── 004_programs.sql
│   │   ├── 005_virtual_records.sql
│   │   ├── 006_nursing_and_appointments.sql
│   │   ├── 007_functions.sql
│   │   ├── 008_permissions.sql
│   │   ├── 009_role_changes_normalization.sql
│   │   ├── 011_virtual_file_procedures.sql
│   │   └── 012_user_roles_foundation.sql
│   └── seeds/
│       └── 000_seed_roles.sql
└── AGENTS.md
```

**Note on numbering:** Migrations `011` and `012` were originally `009_virtual_file_procedures.sql` and `010_user_roles_foundation.sql` but were renumbered to resolve a conflict where two files shared the `009` prefix.

---

## 3. Tables (~30)

Core tables by domain:

- **Auth:** `roles`, `users`, `user_two_factor`, `user_sessions`, `login_attempts`, `password_reset_tokens`, `email_verification_tokens`
- **Access:** `entrances_exits`
- **Roles audit:** `role_changes`
- **Older adults:** `older_adult`, `older_adult_family`, `older_adult_updates`, `older_adult_subprogram`
- **Clinical:** `clinical_history`, `clinical_conditions`, `clinical_medications`, `clinical_history_and_conditions`, `vaccines`, `vaccines_and_clinical_history`
- **Programs:** `programs`, `sub_programs`
- **Nursing:** `nursing_records`, `specialized_appointment`, `specialized_area`, `physiotherapy_sessions`, `psychology_sessions`, `social_work_reports`, `medical_record`
- **Audit / logs:** `audit_reports`, `digital_records`, `notifications`, `notification_attachments`
- **Emergency contacts:** `emergency_contacts`

For schema inspection, use **Supabase Dashboard → Schema Editor** or query `information_schema` tables.

---

## 4. Naming conventions

- **Tables:** snake_case, mostly plural (`users`, `roles`, `nursing_records`), some singular legacy (`older_adult`)
- **Columns:** snake_case. Legacy prefixes: `u_` (user), `r_` (role), `tfa_` (2FA), `rpt_` (report), `not_` (notification)
- **PKs:** `id` INTEGER GENERATED BY DEFAULT AS IDENTITY
- **FKs:** `<table>_id` (`user_id`, `role_id`)
- **Timestamps:** `created_at`, `updated_at` (TIMESTAMPTZ)
- **Soft delete:** `is_active` boolean

---

## 5. Adding a new table — checklist

1. Create a new migration file: `supabase/migrations/013_<table_name>.sql` (use next available number)
2. Write idempotent SQL: `CREATE TABLE IF NOT EXISTS`, add indexes
3. Add the corresponding TypeORM entity in the backend (`src/ucr/ac/cr/ie/domain/<area>/<thing>.entity.ts`)
4. **Add the entity to `database.providers.ts`** (see `backend/docs/entities.md`)
5. Update this file (Section 3) if the table is core to the domain
6. Commit: `feat(db): add <table> table`

---

## 6. Modifying a table — checklist

1. **Do not drop columns** without an `ALTER TABLE ... DROP COLUMN` in a new migration
2. **Do not rename columns** without updating both the migration and the backend entity in the same commit
3. **Do not change types** without a proper migration path (add new column, migrate data, drop old)
4. Create a new numbered migration file (do NOT edit existing migrations)
5. Commit: `feat(db): add <column> to <table>` or `fix(db): ...`

---

## 7. Migration order

Migrations are executed in alphabetical order by filename. Current order:

| #  | File | Purpose |
|----|------|---------|
| 001 | `extensions_and_types.sql` | Enable `pgcrypto`, `citext`; create ENUM types |
| 002 | `core_auth.sql` | `roles`, `users`, `user_two_factor`, `user_sessions`, `login_attempts`, `password_reset_tokens`, `email_verification_tokens`, `role_changes` |
| 003 | `access_and_audit.sql` | `entrances_exits`, `digital_record`, `audit_reports`, `notifications`, `notification_attachment` |
| 004 | `programs.sql` | `programs`, `sub_programs` |
| 005 | `virtual_records.sql` | `older_adult_family`, `older_adult`, `older_adult_subprogram`, `emergency_contacts`, `clinical_*`, `vaccines` |
| 006 | `nursing_and_appointments.sql` | `specialized_area`, `specialized_appointment`, `nursing_records`, `physiotherapy_sessions`, `psychology_sessions`, `social_work_reports`, `medical_record` |
| 007 | `functions.sql` | `clean_expired_sessions()`, `clean_expired_tokens()`, `get_failed_login_stats()`, `log_audit()`, `set_updated_at()` trigger |
| 008 | `permissions.sql` | `permissions`, `role_permissions` (RBAC catalogue + per-role seeds) |
| 009 | `role_changes_normalization.sql` | Add nullable `old_role_id` / `new_role_id` FKs to `role_changes` |
| 011 | `virtual_file_procedures.sql` | `create_virtual_file()`, `delete_virtual_file()`, `get_virtual_file()`, `compute_audit_session_duration()` |
| 012 | `user_roles_foundation.sql` | Additional role-related tables |
| — | `seeds/000_seed_roles.sql` | Default roles (8 total) |

**Note:** There is no `010_*.sql` — the original `010_user_roles_foundation.sql` was renumbered to `012` to resolve the `009` collision.

---

## 8. Common queries (PostgreSQL)

### 8.1 List all tables

```sql
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;
```

### 8.2 List columns of a table

```sql
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'users'
ORDER BY ordinal_position;
```

### 8.3 List foreign keys of a table

```sql
SELECT
  tc.constraint_name,
  kcu.column_name,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
WHERE tc.table_name = 'users'
  AND tc.constraint_type = 'FOREIGN KEY';
```

### 8.4 Find orphaned rows (broken FKs — should be zero)

```sql
SELECT u.id, u.role_id
FROM users u
LEFT JOIN roles r ON r.id = u.role_id
WHERE r.id IS NULL AND u.role_id IS NOT NULL;
```

---

## 9. How to apply migrations

### Option A — Supabase Dashboard (recommended for first-time)

1. Open your Supabase project → **SQL Editor**
2. Run files in order (001 → 012)
3. Optionally run `seeds/000_seed_roles.sql`

### Option B — Supabase CLI

```bash
# from the repo root
supabase db push
```

### Option C — Direct psql

```bash
psql "$DATABASE_URL" -f supabase/migrations/001_extensions_and_types.sql
psql "$DATABASE_URL" -f supabase/migrations/002_core_auth.sql
# ... repeat for all migrations
```

---
