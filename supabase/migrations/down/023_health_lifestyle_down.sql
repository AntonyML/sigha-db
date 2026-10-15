-- =============================================================================
-- 023_health_lifestyle_down.sql
-- Reversión de la migración 023 (health_lifestyle)
-- =============================================================================

DROP TABLE IF EXISTS patient_lifestyle_assessments CASCADE;
DROP FUNCTION IF EXISTS trg_set_timestamp_lifestyle() CASCADE;

DROP TYPE IF EXISTS e_alcohol_status CASCADE;
DROP TYPE IF EXISTS e_smoking_status CASCADE;
DROP TYPE IF EXISTS e_physical_activity_level CASCADE;
DROP TYPE IF EXISTS e_sleep_quality CASCADE;
DROP TYPE IF EXISTS e_appetite_level CASCADE;
DROP TYPE IF EXISTS e_diet_type CASCADE;
