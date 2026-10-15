-- =============================================================================
-- 030_organization_member_role.sql
-- One organization role per membership + platform-owner backfill.
--
-- - Adds organization_members.role_id (FK -> roles) and makes it NOT NULL.
-- - Backfills each membership from the member's legacy users.role_id:
--     * legacy 'super admin' (role 1) -> 'admin' (role 2)
--     * legacy NULL                   -> 'not specified' (role 8)
--     * otherwise                     -> the legacy role
-- - Promotes legacy 'super admin' users to users.platform_role = 'PLATFORM_OWNER'.
-- - Removes the 'super admin' role from the organization role catalog.
-- Idempotent-ish: re-running the column/FK/index is a no-op; the DELETE is safe.
-- Run after 029.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Membership role column (nullable first, so it can be backfilled).
-- -----------------------------------------------------------------------------
ALTER TABLE public.organization_members
  ADD COLUMN IF NOT EXISTS role_id INTEGER;

COMMENT ON COLUMN public.organization_members.role_id IS
  'Single organization role of the membership (one role per membership).';

-- -----------------------------------------------------------------------------
-- 2. Backfill role_id from the legacy users.role_id.
--    DISTINCT ON (user_id) derives one legacy role per user before applying it
--    to every membership of that user.
-- -----------------------------------------------------------------------------
WITH legacy AS (
  SELECT DISTINCT ON (u.id)
         u.id AS user_id,
         u.role_id
    FROM public.users AS u
   ORDER BY u.id
)
UPDATE public.organization_members AS om
   SET role_id = CASE
                   WHEN legacy.role_id = 1 THEN 2   -- super admin -> admin
                   WHEN legacy.role_id IS NULL THEN 8 -- no legacy role -> not specified
                   ELSE legacy.role_id
                 END
  FROM legacy
 WHERE om.user_id = legacy.user_id
   AND om.role_id IS NULL;

-- -----------------------------------------------------------------------------
-- 3. Promote legacy 'super admin' users to platform owners (before the role is
--    removed, while users.role_id still identifies them).
-- -----------------------------------------------------------------------------
UPDATE public.users
   SET platform_role = 'PLATFORM_OWNER'
 WHERE role_id = 1
   AND platform_role IS DISTINCT FROM 'PLATFORM_OWNER';

-- -----------------------------------------------------------------------------
-- 4. Enforce one non-null role per membership.
-- -----------------------------------------------------------------------------
ALTER TABLE public.organization_members
  ALTER COLUMN role_id SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_organization_members_role'
  ) THEN
    ALTER TABLE public.organization_members
      ADD CONSTRAINT fk_organization_members_role
      FOREIGN KEY (role_id) REFERENCES public.roles (id) ON DELETE RESTRICT;
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_organization_members_role_id
  ON public.organization_members (role_id);

-- -----------------------------------------------------------------------------
-- 5. Remove 'super admin' from the organization role catalog.
--    users.role_id is ON DELETE SET NULL and user_roles/role_permissions cascade,
--    so the legacy references are cleaned up automatically.
-- -----------------------------------------------------------------------------
DELETE FROM public.roles WHERE id = 1;

-- End of 030.
