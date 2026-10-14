# AGENTS.md — Database (`sigha-db/`)

> **You are an AI agent working on the Supabase/Postgres database of the Sistema Integral de Gestión Holística y de Asistencia (SIGHA) platform.**
> This file contains the database-specific rules and the shared Git workflow for this repository.

---

## 0. Scope and authority

- **Work only in the `sigha-db` repository.** Cross-repository work is a separate task (`taskId`) with its own worktree in the target repository.
- **You never `push`** to the remote. The human reviews and publishes `dev` and `main`.
- **You do not amend** published commits.
- **You do not** commit production data dumps (only structure, migrations, and seed data).
- You **do** integrate your finished branch into `dev` locally under the `dev-sigha-db` lock, re-verify there, and clean up your worktree/branch — but you never `push`.

## Coordinación y Git (protocolo multi-agente)

> Protocolo maestro: `C:\DEV\sigha\AGENTS.md` — **manda sobre esta sección**.
> Registro: `C:\DEV\sigha\_wt\_registry\sigha-db.jsonl` (formato en `_wt\_registry\README.md`).

### Identidad y alcance

Al iniciar, identifícate con:

```
Agente: <herramienta>/<modelo> | repo: sigha-db | taskId: <taskId o "(por reclamar)">
| rama: task/<taskId> | worktree: C:\DEV\sigha\_wt\sigha-db\<taskId>
| archivos: <alcance> | base: <sha de dev> | migración: <NNN>
```

La identidad es el **`taskId`** (`sigha-db-<yyyymmdd>-<rand4>`), no la herramienta. La herramienta/modelo se registran solo como `actor`. El número de migración se **reserva de forma atómica** al reclamar (unicidad en el ledger): una tarea, un número. Contratos compartidos con api/web (esquema ↔ entidades ↔ DTOs) se acuerdan **antes** de trabajar en paralelo, no durante.

### Checkout principal: solo se integra

- `C:\DEV\sigha\sigha-db` **siempre está en `dev`, siempre está limpio.** No se edita a mano: solo se integra ahí una rama terminada, bajo el lock `dev-sigha-db`.
- Prohibido para agentes: editarlo directamente, hacer `checkout`/`switch` en él, commitear dumps de producción (solo estructura, migraciones y seeds).

### Tu worktree (uno por tarea)

- Ruta canónica: `C:\DEV\sigha\_wt\sigha-db\<taskId>`, rama `task/<taskId>` creada desde `origin/dev` recién traído. ⛔ Ruta vieja `~/worktrees/...` deprecada: no crear nada ahí.
- Si no existe `origin/dev` ni `dev`, STOP y pide al humano que fije `dev`. `main` queda reservada: no basar ramas en ella ni integrarle nada.
- Secuencia obligatoria (una operación Git a la vez; con lock: esperar, nunca borrar `.lock` con proceso vivo):
  1. `git -C C:\DEV\sigha\sigha-db worktree list` + `status --short --branch` + `log --oneline -5` (solo lectura).
  2. Preflight (§6 del protocolo): lee los tres ledgers; si hay solape de archivos o de número de migración, o tarea `blocked` con pregunta abierta → HARD STOP.
  3. Bajo `registry-sigha-db.lock`: si ningún claim abierto cubre tus archivos ni tu número → appendea tu `claim` (`status: in_progress`) con un `taskId` único y el número de migración reservado.
  4. `git -C C:\DEV\sigha\sigha-db fetch origin dev` y `worktree add "C:\DEV\sigha\_wt\sigha-db\<taskId>" -b "task/<taskId>" origin/dev`.
- No compartas worktree, rama ni sesión de edición. No hagas `push` ni `rebase` por tu cuenta ni `amend` de commits publicados.
- CodeGraph: cada worktree usa su propio `.codegraph/` (`gentle-ai codegraph init --cwd <tu-worktree>` si falta); no copiar ni compartir índices.

### Migraciones en paralelo (reserva obligatoria)

- El número de migración se reserva **antes** de trabajar (ej. `013_...`, `014_...`, uno distinto por tarea), de forma atómica bajo el lock de registro y con unicidad comprobada en el ledger.
- **No edites migraciones ya aplicadas** (001–012 y cualquiera integrada en `dev`): todo cambio va en un archivo nuevo numerado. SQL idempotente (`CREATE TABLE IF NOT EXISTS`, índices).

### Regla STOP ante diffs ajenos

Si `status`/`diff` muestra SQL que no escribiste, otro proceso tocó tu migración o un `log` trae commits inesperados: **para de editar, no sobrescribas, no hagas commit "para salvar lo tuyo"**. Diagnostica en solo lectura (`status`, `diff --stat`, `log --oneline -5` en tu worktree, relee el archivo, compara con tu claim y con los ledgers) y reporta al humano archivo + cambio inesperado + tu `baseSha` vs `HEAD` + `taskId`/rama sospechosa. **"Releer y seguir" sin atribuir el cambio está prohibido.** Detalle en `C:\DEV\sigha\AGENTS.md` §7.

### Entrega e integración (tú integras; el humano solo hace `push`)

1. Commit en tu rama, `git status` limpio, y appendea `event: "done"` con `branch`, `worktree`, `baseSha`, número de migración, `git diff --stat`, archivos y verificaciones con resultado.
2. Bajo el lock `dev-sigha-db`: con el checkout principal en `dev` y limpio, `fetch origin dev` y `merge --no-ff "task/<taskId>"`. Si hay conflicto → `merge --abort`, marca `blocked`, conserva el worktree, HARD STOP.
3. **Re-verifica en `dev`**: valida la migración en el proyecto Supabase de desarrollo (nunca producción), confirma el destino y comprueba el esquema/comportamiento afectados. Que pase en el worktree no basta.
4. Si pasa: actualiza `CHANGELOG.md`, commitea en `dev`, appendea `event: "integrated"` con `mergeSha`/`devSha`, y limpia worktree + rama (`worktree remove`, `branch -d`, `worktree prune`).
5. Si falla la re-verificación: `git revert -m 1 <mergeSha>`, marca `blocked`, conserva el worktree y HARD STOP. Si la migración ya se aplicó, `git revert` no revierte el esquema: crea y valida una migración correctiva nueva; nunca edites la migración aplicada.
6. **No hagas `push`.** El humano revisa `dev` y publica `dev` y `main`.

Formato de la línea de `CHANGELOG.md`: `YYYY-MM-DD | <taskId> | tipo: resumen | verificación: resultado`.

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
│   │   ├── 012_user_roles_foundation.sql
│   │   ├── 013_system_user.sql
│   │   ├── 014_system_user_email.sql
│   │   ├── 015_organizations.sql
│   │   ├── 016_older_adult_location.sql
│   │   ├── 017_document_type.sql
│   │   ├── 018_roles_name_to_varchar.sql
│   │   ├── 019_virtual_file_required_family.sql
│   │   ├── 020_delete_virtual_file_cascade_updates.sql
│   │   └── 021_catalogs_medications_vaccines.sql
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
| 013 | `system_user.sql` | Reserved system user for automated/audit actions |
| 014 | `system_user_email.sql` | Update the reserved system user's email to the SIGHA identity |
| 015 | `organizations.sql` | `organizations`, `organization_members`, and ASOPOGUA membership seed |
| 016 | `older_adult_location.sql` | Structured province/canton/district for older adults |
| 017 | `document_type.sql` | Document type for older adults and family members |
| 018 | `roles_name_to_varchar.sql` | Allow custom role names up to 100 characters |
| 019 | `virtual_file_required_family.sql` | `create_virtual_file()`: full family required, document types persisted, conditional validations |
| 020 | `020_delete_virtual_file_cascade_updates.sql` | `older_adult_updates.fk_oau_adult` ON DELETE CASCADE y `delete_virtual_file()` defensivo |
| 021 | `021_catalogs_medications_vaccines.sql` | Catálogo CIE-10, `patient_conditions`, vademécum, `medication_prescriptions`, Kardex MAR `medication_administrations` y `patient_vaccinations` |
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
