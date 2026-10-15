-- Give each clinical and administrative module its own permission key.
-- Permission module keys grow with the product, so they are stored as text
-- instead of requiring an enum migration for every new module.
ALTER TABLE public.permissions
  ALTER COLUMN p_module TYPE VARCHAR(32) USING p_module::TEXT;

ALTER TABLE public.permissions
  ADD CONSTRAINT ck_permissions_module_key CHECK (p_module IN (
    'users','roles','permissions','dashboard','virtualFiles','audits','programs',
    'vaccines','subPrograms','entranceExit','twoFactor','nursing','physiotherapy',
    'psychology','socialWork','clinicalHistory','clinicalMedication','medicalRecords',
    'emergencyContacts','olderAdultFamily','olderAdultUpdates','specializedAreas',
    'specializedAppointments','settings','carePlans','accessLogs','systemAudit','beds','lifestyle'
  ));

INSERT INTO public.permissions (p_name, p_description, p_module, p_action)
SELECT module.permission_name, module.description, module.module_key, action.action_key::public.e_permission_action
FROM (VALUES
  ('carePlans', 'Planes de cuidado', 'Inscripciones, metas y seguimiento de programas de cuidado'),
  ('accessLogs', 'Entradas y salidas', 'Registro de salidas, entradas y visitas'),
  ('beds', 'Censo y camas', 'Gestión del censo residencial y de camas'),
  ('lifestyle', 'Estilo de vida', 'Evaluaciones de estilo de vida y hábitos'),
  ('systemAudit', 'Auditoría administrativa', 'Consulta de auditoría administrativa de solo lectura')
) AS module(module_key, permission_name, description)
CROSS JOIN (VALUES ('view'), ('create'), ('edit'), ('delete')) AS action(action_key)
WHERE module.module_key <> 'systemAudit' OR action.action_key = 'view'
ON CONFLICT (p_module, p_action) DO NOTHING;

-- New catalogue entries are deliberately separate from the legacy
-- programs/subPrograms/entranceExit permission keys.
INSERT INTO public.role_permissions (role_id, permission_id, rp_granted)
SELECT role.id, permission.id,
  CASE
    WHEN role_name = 'super admin' THEN TRUE
    WHEN role_name = 'admin' THEN permission.p_action <> 'delete'
      AND (permission.p_module <> 'systemAudit' OR permission.p_action = 'view')
    WHEN role_name = 'director' THEN permission.p_action = 'view'
      OR (permission.p_module IN ('carePlans','accessLogs','beds','lifestyle')
          AND permission.p_action IN ('create','edit'))
    WHEN role_name = 'nurse' THEN permission.p_module IN ('carePlans','accessLogs','beds','lifestyle')
      AND permission.p_action IN ('view','create','edit')
    WHEN role_name IN ('physiotherapist','psychologist') THEN
      (permission.p_module IN ('carePlans','lifestyle') AND permission.p_action IN ('view','create','edit'))
      OR (permission.p_module = 'beds' AND permission.p_action = 'view')
    WHEN role_name = 'social worker' THEN
      (permission.p_module IN ('carePlans','accessLogs','lifestyle') AND permission.p_action IN ('view','create','edit'))
      OR (permission.p_module = 'beds' AND permission.p_action = 'view')
    ELSE FALSE
  END
FROM public.roles AS role
CROSS JOIN public.permissions AS permission
CROSS JOIN LATERAL (SELECT lower(trim(role.r_name)) AS role_name) AS normalized
WHERE permission.p_module IN ('carePlans','accessLogs','systemAudit','beds','lifestyle')
ON CONFLICT (role_id, permission_id) DO NOTHING;
