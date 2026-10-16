-- Keep the tenant user creation contract aligned with migration 030, which
-- requires every organization membership to have exactly one role.
CREATE OR REPLACE FUNCTION public.create_tenant_user(
  p_identification TEXT,
  p_name TEXT,
  p_f_last_name TEXT,
  p_s_last_name TEXT,
  p_email TEXT,
  p_password_hash TEXT
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_tenant_id INTEGER := NULLIF(current_setting('app.current_tenant_id',true),'')::INTEGER;
  v_actor_id INTEGER := NULLIF(current_setting('app.current_user_id',true),'')::INTEGER;
  v_user_id INTEGER;
  v_default_role_id INTEGER;
  v_default_role_count INTEGER;
BEGIN
  IF v_tenant_id IS NULL OR v_actor_id IS NULL THEN
    RAISE EXCEPTION 'Tenant and actor context are required to create a user' USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.organization_members member
    JOIN public.organizations org ON org.id = member.organization_id
    WHERE member.organization_id = v_tenant_id AND member.user_id = v_actor_id AND org.is_active
  ) THEN
    RAISE EXCEPTION 'Actor is not an active member of this organization' USING ERRCODE='42501';
  END IF;

  SELECT count(*)::INTEGER, min(role.id)
    INTO v_default_role_count, v_default_role_id
    FROM public.roles role
   WHERE lower(trim(role.r_name)) = 'not specified';
  IF v_default_role_count <> 1 THEN
    RAISE EXCEPTION 'The organization role "not specified" must exist exactly once' USING ERRCODE='55000';
  END IF;

  INSERT INTO public.users(u_identification,u_name,u_f_last_name,u_s_last_name,u_email,u_password)
  VALUES(p_identification,p_name,p_f_last_name,p_s_last_name,p_email,p_password_hash)
  RETURNING id INTO v_user_id;

  INSERT INTO public.organization_members(user_id,organization_id,role_id,is_primary)
  VALUES(v_user_id,v_tenant_id,v_default_role_id,TRUE);
  RETURN v_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_tenant_user(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_tenant_user(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT) TO sigha_app;
