-- =============================================================================
-- 029_organization_platform_fields.sql
-- SaaS platform plane: organization lifecycle, plan tier and branding on
-- public.organizations.
--
-- Additive and idempotent. The legacy is_active column is preserved for
-- backwards compatibility and backfilled into the new status column.
-- Run after 028.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. ENUMs.
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
     WHERE t.typname = 'e_organization_status' AND n.nspname = 'public'
  ) THEN
    CREATE TYPE public.e_organization_status AS ENUM ('ACTIVE', 'SUSPENDED', 'ARCHIVED');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
     WHERE t.typname = 'e_plan_tier' AND n.nspname = 'public'
  ) THEN
    CREATE TYPE public.e_plan_tier AS ENUM ('BASIC', 'STANDARD', 'PREMIUM', 'ENTERPRISE');
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- 2. Columns.
-- -----------------------------------------------------------------------------
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS status public.e_organization_status NOT NULL DEFAULT 'ACTIVE',
  ADD COLUMN IF NOT EXISTS plan_tier public.e_plan_tier NOT NULL DEFAULT 'BASIC',
  ADD COLUMN IF NOT EXISTS branding_overrides JSONB;

COMMENT ON COLUMN public.organizations.status IS
  'Organization lifecycle status (tenant plane); ACTIVE is required by the tenant guard.';
COMMENT ON COLUMN public.organizations.plan_tier IS
  'Commercial plan tier of the organization (SaaS platform plane).';
COMMENT ON COLUMN public.organizations.branding_overrides IS
  'Per-organization branding overrides as a JSON object; NULL means use platform defaults.';

-- -----------------------------------------------------------------------------
-- 3. Backfill status from legacy is_active (idempotent).
-- -----------------------------------------------------------------------------
UPDATE public.organizations
   SET status = 'ACTIVE'
 WHERE is_active IS DISTINCT FROM FALSE
   AND status IS DISTINCT FROM 'ACTIVE';

UPDATE public.organizations
   SET status = 'SUSPENDED'
 WHERE is_active = FALSE
   AND status IS DISTINCT FROM 'SUSPENDED';

-- -----------------------------------------------------------------------------
-- 4. branding_overrides, when present, must be a JSON object.
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_organizations_branding_overrides_object'
  ) THEN
    ALTER TABLE public.organizations
      ADD CONSTRAINT chk_organizations_branding_overrides_object
      CHECK (branding_overrides IS NULL OR jsonb_typeof(branding_overrides) = 'object');
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- 5. Index for filtering by lifecycle status.
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_organizations_status
  ON public.organizations (status);

-- End of 029.
