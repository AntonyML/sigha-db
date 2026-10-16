-- =============================================================================
-- 027_platform_role.sql
-- SaaS platform plane: distinguish platform-level roles (Platform Owner /
-- Platform Support) from organization (tenant) roles.
--
-- Additive and idempotent: every existing row keeps platform_role = NULL, so
-- tenant behaviour is unchanged. Assigning platform roles and the tenant
-- role -> membership migration happen in later migrations.
-- Run after 026.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Platform role ENUM.
--    Deliberately separate from e_user_role: organization roles belong to a
--    tenant, platform roles belong to the SaaS operator.
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM pg_type t
      JOIN pg_namespace n ON n.oid = t.typnamespace
     WHERE t.typname = 'e_platform_role'
       AND n.nspname = 'public'
  ) THEN
    CREATE TYPE public.e_platform_role AS ENUM ('PLATFORM_OWNER', 'PLATFORM_SUPPORT');
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- 2. users.platform_role: NULL for every regular (tenant) user.
-- -----------------------------------------------------------------------------
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS platform_role public.e_platform_role;

COMMENT ON COLUMN public.users.platform_role IS
  'NULL for tenant users; PLATFORM_OWNER/PLATFORM_SUPPORT grant access to the platform (SaaS) plane.';

-- -----------------------------------------------------------------------------
-- 3. Partial index for the (rare) platform accounts.
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_users_platform_role
  ON public.users (platform_role)
  WHERE platform_role IS NOT NULL;

-- End of 027.
