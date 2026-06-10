-- =============================================================================
-- 001_extensions_and_types.sql
-- Supabase / PostgreSQL extensions and custom ENUM types.
-- Run first.
-- =============================================================================

-- Recommended extensions for Supabase projects.
CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- gen_random_uuid(), digest()
CREATE EXTENSION IF NOT EXISTS "citext";     -- case-insensitive text (optional, for emails)

-- -----------------------------------------------------------------------------
-- ENUM types — converted from MySQL ENUMs.
-- Naming: e_<column> for table-specific ENUMs, t_<concept> for shared ones.
-- Postgres does not allow ALTER TYPE ... ADD VALUE inside a transaction
-- without a separate statement, so prefer TEXT + CHECK if you need flexibility.
-- -----------------------------------------------------------------------------

CREATE TYPE e_user_role AS ENUM (
  'super admin',
  'admin',
  'director',
  'nurse',
  'physiotherapist',
  'psychologist',
  'social worker',
  'not specified'
);

CREATE TYPE e_two_factor_action AS ENUM (
  -- Reserved for future expansion of 2FA audit.
  'enable', 'disable', 'regenerate_backup_codes', 'verify_success', 'verify_failure'
);

CREATE TYPE e_audit_action AS ENUM (
  'create', 'update', 'delete', 'view', 'login', 'logout', 'export', 'other'
);

CREATE TYPE e_audit_type AS ENUM (
  'general_actions',
  'role_changes',
  'older_adult_updates',
  'system_access',
  'login_attempts',
  'password_resets',
  'clinical_record_changes',
  'notifications',
  'other'
);

CREATE TYPE e_oa_marital_status AS ENUM (
  'single', 'married', 'divorced', 'widowed',
  'common law union', 'separated', 'not specified'
);

CREATE TYPE e_oa_years_schooling AS ENUM (
  'no schooling', 'incomplete primary', 'complete primary',
  'incomplete secondary', 'complete secondary', 'technical degree',
  'incomplete university', 'complete university', 'postgraduate', 'not specified'
);

CREATE TYPE e_oa_status AS ENUM ('alive', 'dead');

CREATE TYPE e_oa_gender AS ENUM ('male', 'female', 'not specified');

CREATE TYPE e_oa_blood_type AS ENUM (
  'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'UNKNOWN'
);

CREATE TYPE e_pf_kinship AS ENUM (
  'son', 'daughter', 'grandson', 'granddaughter', 'brother', 'sister',
  'nephew', 'niece', 'husband', 'wife', 'legal guardian', 'other', 'not specified'
);

CREATE TYPE e_clinical_rcvg AS ENUM (
  '< 10%', 'e /10y20%', 'e /20y30%', 'e /40y40%', '> 40%', 'UNKNOWN'
);

CREATE TYPE e_medication_treatment_type AS ENUM (
  'temporary', 'chronic', 'preventive', 'other'
);

CREATE TYPE e_entrance_exit_type AS ENUM (
  'employee', 'older adult', 'visitor', 'volunteer', 'vehicle', 'other'
);

CREATE TYPE e_entrance_exit_access AS ENUM ('entrance', 'exit');

CREATE TYPE e_specialized_area_name AS ENUM (
  'nursing', 'physiotherapy', 'psychology', 'social_work', 'not specified'
);

CREATE TYPE e_appointment_type AS ENUM (
  'checkup', 'evaluation', 'therapy', 'follow_up', 'emergency'
);

CREATE TYPE e_appointment_priority AS ENUM (
  'low', 'medium', 'high', 'urgent'
);

CREATE TYPE e_appointment_status AS ENUM (
  'scheduled', 'in_progress', 'completed', 'cancelled', 'rescheduled'
);

CREATE TYPE e_nursing_mobility AS ENUM (
  'independent', 'assisted', 'bedridden'
);

CREATE TYPE e_nursing_quality AS ENUM ('good', 'regular', 'poor');

CREATE TYPE e_physio_session_type AS ENUM (
  'evaluation', 'therapy', 'follow_up'
);

CREATE TYPE e_physio_mobility_level AS ENUM (
  'high', 'moderate', 'low', 'none'
);

CREATE TYPE e_psy_session_type AS ENUM (
  'evaluation', 'therapy', 'follow_up', 'group therapy'
);

CREATE TYPE e_psy_mood AS ENUM (
  'stable', 'anxious', 'depressed', 'irritable', 'other'
);

CREATE TYPE e_psy_cognitive_status AS ENUM (
  'normal', 'mild impairment', 'moderate impairment', 'severe impairment'
);

CREATE TYPE e_sw_visit_type AS ENUM (
  'home visit', 'institutional visit', 'interview', 'follow_up'
);

CREATE TYPE e_dr_action AS ENUM (
  'login', 'logout', 'create', 'update', 'delete', 'view', 'export', 'other'
);

CREATE TYPE e_notification_status AS ENUM ('pending', 'sent', 'failed', 'read');

-- End of 001.
