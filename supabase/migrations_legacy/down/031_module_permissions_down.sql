DELETE FROM public.role_permissions AS rp
USING public.permissions AS permission
WHERE rp.permission_id = permission.id
  AND permission.p_module IN ('carePlans','accessLogs','systemAudit','beds','lifestyle');

DELETE FROM public.permissions
WHERE p_module IN ('carePlans','accessLogs','systemAudit','beds','lifestyle');

ALTER TABLE public.permissions
  DROP CONSTRAINT IF EXISTS ck_permissions_module_key;

ALTER TABLE public.permissions
  ALTER COLUMN p_module TYPE public.e_permission_module USING p_module::public.e_permission_module;
