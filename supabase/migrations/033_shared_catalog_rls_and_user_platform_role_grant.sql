-- =============================================================================
-- 033_shared_catalog_rls_and_user_platform_role_grant.sql
-- Align tenant runtime role (sigha_app) with migration 027 and shared catalogs:
-- 1. Grant SELECT (platform_role) on public.users to sigha_app so tenant-scoped
--    queries that join or select User entities (e.g., notifications.sender) do
--    not fail with "permission denied for table users".
-- 2. Add explicit RLS policies for sigha_app on shared authorization and
--    clinical reference catalogues that have Row Level Security enabled without
--    tenant_id columns (roles, permissions, role_permissions, clinical_conditions,
--    vaccines, specialized_area, medication_catalog, icd10_catalog, system_settings).
-- =============================================================================

GRANT SELECT (platform_role) ON public.users TO sigha_app;

DO $$
DECLARE
  v_table TEXT;
  v_shared_tables TEXT[] := ARRAY[
    'roles',
    'permissions',
    'role_permissions',
    'clinical_conditions',
    'vaccines',
    'specialized_area',
    'medication_catalog',
    'icd10_catalog',
    'system_settings'
  ];
BEGIN
  FOREACH v_table IN ARRAY v_shared_tables LOOP
    IF to_regclass(format('public.%I', v_table)) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', v_table);
      EXECUTE format('DROP POLICY IF EXISTS shared_catalog_sigha_app_policy ON public.%I', v_table);
      EXECUTE format(
        'CREATE POLICY shared_catalog_sigha_app_policy ON public.%I FOR ALL TO sigha_app USING (true) WITH CHECK (true)',
        v_table
      );
    END IF;
  END LOOP;
END;
$$;
