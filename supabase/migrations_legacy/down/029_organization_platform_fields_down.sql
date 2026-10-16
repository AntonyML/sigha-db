-- =============================================================================
-- 029_organization_platform_fields_down.sql
-- Reverts migration 029: organizations.status, plan_tier, branding_overrides,
-- their constraint, index and the new ENUM types.
-- =============================================================================

DROP INDEX IF EXISTS public.idx_organizations_status;
ALTER TABLE public.organizations DROP CONSTRAINT IF EXISTS chk_organizations_branding_overrides_object;
ALTER TABLE public.organizations DROP COLUMN IF EXISTS branding_overrides;
ALTER TABLE public.organizations DROP COLUMN IF EXISTS plan_tier;
ALTER TABLE public.organizations DROP COLUMN IF EXISTS status;
DROP TYPE IF EXISTS public.e_organization_status;
DROP TYPE IF EXISTS public.e_plan_tier;

-- End of 029 down.
