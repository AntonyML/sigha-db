-- =============================================================================
-- 022_revert_clinical_encounters_nursing_specialties.sql
-- Reversión de la migración 022.
-- Elimina tablas y tipos asociados a encuentros clínicos, rondas, signos vitales,
-- evaluaciones geriátricas especializadas, camas y habitaciones.
-- =============================================================================

DROP TABLE IF EXISTS social_work_evaluations CASCADE;
DROP TABLE IF EXISTS psychology_evaluations CASCADE;
DROP TABLE IF EXISTS physiotherapy_evaluations CASCADE;
DROP TABLE IF EXISTS clinical_note_addendums CASCADE;
DROP TABLE IF EXISTS nursing_rounds CASCADE;
DROP TABLE IF EXISTS clinical_vital_signs CASCADE;
DROP TABLE IF EXISTS clinical_encounters CASCADE;
DROP TABLE IF EXISTS patient_bed_assignments CASCADE;
DROP TABLE IF EXISTS facility_rooms CASCADE;

DROP TYPE IF EXISTS e_apgar_level CASCADE;
DROP TYPE IF EXISTS e_pfeiffer_level CASCADE;
DROP TYPE IF EXISTS e_gds_level CASCADE;
DROP TYPE IF EXISTS e_barthel_level CASCADE;
DROP TYPE IF EXISTS e_nursing_shift CASCADE;
DROP TYPE IF EXISTS e_encounter_type CASCADE;
DROP TYPE IF EXISTS e_encounter_status CASCADE;
DROP TYPE IF EXISTS e_encounter_class CASCADE;
