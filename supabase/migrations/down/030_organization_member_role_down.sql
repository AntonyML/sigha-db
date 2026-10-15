-- =============================================================================
-- 030_organization_member_role_down.sql
-- Reverts migration 030.
-- NOTE: the data effects are best-effort. Once the 'super admin' role has been
-- deleted and users.role_id was set to NULL in cascade, the original per-user
-- legacy role cannot be reconstructed from the database alone.
-- =============================================================================

ALTER TABLE public.organization_members DROP CONSTRAINT IF EXISTS fk_organization_members_role;
DROP INDEX IF EXISTS public.idx_organization_members_role_id;
ALTER TABLE public.organization_members DROP COLUMN IF EXISTS role_id;

INSERT INTO public.roles (id, r_name) VALUES (1, 'super admin')
ON CONFLICT (id) DO NOTHING;

UPDATE public.users
   SET platform_role = NULL
 WHERE platform_role = 'PLATFORM_OWNER';

-- End of 030 down.
