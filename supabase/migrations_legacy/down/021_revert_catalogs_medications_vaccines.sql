-- =============================================================================
-- 021_revert_catalogs_medications_vaccines.sql
-- Revierte la migración 021 en caso de rollback.
-- =============================================================================

-- 1. Eliminar triggers
DROP TRIGGER IF EXISTS trg_medication_prescriptions_updated_at ON public.medication_prescriptions;
DROP TRIGGER IF EXISTS trg_patient_conditions_updated_at ON public.patient_conditions;

-- 2. Eliminar tablas en orden inverso de dependencias
DROP TABLE IF EXISTS public.patient_vaccinations CASCADE;
DROP TABLE IF EXISTS public.medication_administrations CASCADE;
DROP TABLE IF EXISTS public.medication_prescriptions CASCADE;
DROP TABLE IF EXISTS public.medication_catalog CASCADE;
DROP TABLE IF EXISTS public.patient_conditions CASCADE;
DROP TABLE IF EXISTS public.icd10_catalog CASCADE;

-- 3. Eliminar tipos ENUM creados en 021
DROP TYPE IF EXISTS public.e_vaccine_dose;
DROP TYPE IF EXISTS public.e_administration_route;
DROP TYPE IF EXISTS public.e_condition_severity;
DROP TYPE IF EXISTS public.e_condition_status;
DROP TYPE IF EXISTS public.e_administration_status;
DROP TYPE IF EXISTS public.e_prescription_status;

-- End of 021 revert.
