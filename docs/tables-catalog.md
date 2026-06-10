# Database tables — reference

> All tables in the `hogar_de_ancianos` schema. Source: `scriptDBCompleta.sql` (~30 tables). Verify the latest schema before relying on exact column names.

---

## Auth and security

| # | Table | Purpose | Notes |
|---|---|---|---|
| 1 | `roles` | System roles | ENUM `r_name` |
| 2 | `users` | Staff accounts | `u_email`, `u_password` (bcrypt hash) |
| 3 | `user_two_factor` | TOTP secret + backup codes per user | `tfa_backup_codes` is JSON |
| 4 | `user_sessions` | Active JWT sessions | `is_active`, `expires_at` |
| 5 | `login_attempts` | Every login attempt (success or failure) | `failure_reason` |
| 6 | `password_reset_tokens` | 8-digit codes (15 min TTL) | hashed |
| 7 | `email_verification_tokens` | Future: email verification | may be unused today |

## Access

| # | Table | Purpose |
|---|---|---|
| 8 | `entrances_exits` | Every entrance/exit event (employees, older adults, visitors) |

## Role history

| # | Table | Purpose |
|---|---|---|
| 9 | `role_changes` | Bitácora de cambios de rol |

## Older adults (core)

| # | Table | Purpose |
|---|---|---|
| 10 | `older_adult` | Core resident record |
| 11 | `older_adult_family` | Family members (M2M-ish) |
| 12 | `older_adult_updates` | Change history of an older adult record |
| 13 | `older_adult_subprogram` | Enrollment in sub-programs |
| 14 | `emergency_contacts` | Emergency contact list per older adult |

## Clinical

| # | Table | Purpose |
|---|---|---|
| 15 | `clinical_history` | Per-adult clinical history |
| 16 | `clinical_conditions` | Master list of clinical conditions |
| 17 | `clinical_history_and_condition` | M2M history ↔ condition |
| 18 | `clinical_medications` | Medications |
| 19 | `vaccines` | Master list of vaccines |
| 20 | `vaccines_and_clinical_history` | M2M history ↔ vaccine |

## Programs

| # | Table | Purpose |
|---|---|---|
| 21 | `programs` | High-level program |
| 22 | `sub_programs` | Sub-program (a session/instance) |

## Nursing

| # | Table | Purpose |
|---|---|---|
| 23 | `nursing_records` | Nursing notes / records |
| 24 | `specialized_appointments` | Appointments to physiotherapy, psychology, etc. |
| 25 | `specialized_areas` | Areas of specialization |

## Audit and notifications

| # | Table | Purpose |
|---|---|---|
| 26 | `audit_reports` | Generated audit reports |
| 27 | `digital_records` | Per-action digital record (audit trail) |
| 28 | `notifications` | In-app notifications |
| 29 | `notification_attachments` | Attachments to notifications |

## Pending / missing

| # | Table | Notes |
|---|---|---|
| 30 | `medical_record` | Referenced in backend plan, verify presence in `scriptDBCompleta.sql` |
| — | `physiotherapy_sessions` | May be implicit in `nursing_records`; verify |
| — | `psychology_sessions` | Same as above |
| — | `social_work_reports` | Same as above |

---

## Notes

- **ENUM** is used in some places (`roles.r_name`). When migrating to Postgres, convert to `CREATE TYPE ... AS ENUM (...)`.
- **JSON columns** (e.g. `tfa_backup_codes`) are MySQL `TEXT` with a JSON string. Postgres equivalent is `JSONB`.
- **`create_at` / `update_at`** are the legacy timestamp names (not `created_at` / `updated_at`). Keep them.

---

## Verifying the live schema

```bash
mysql -u root -p -e "USE hogar_de_ancianos; SHOW TABLES;"
mysql -u root -p -e "USE hogar_de_ancianos; DESCRIBE users;"
```

Or use `make db-check-schema` (if the backend script exists).
