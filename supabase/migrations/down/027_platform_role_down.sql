-- =============================================================================
-- 027_platform_role_down.sql
-- Reverts migration 027: users.platform_role, its partial index and the
-- e_platform_role ENUM.
-- =============================================================================

DROP INDEX IF EXISTS public.idx_users_platform_role;
ALTER TABLE public.users DROP COLUMN IF EXISTS platform_role;
DROP TYPE IF EXISTS public.e_platform_role;

-- End of 027 down.
