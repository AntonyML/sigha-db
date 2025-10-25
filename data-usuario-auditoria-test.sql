USE hogar_de_ancianos;

-- ####################################################################################
-- AUDITORÍA 
-- ####################################################################################
-- 1. Login exitoso de un cuidador
CALL sp_log_audit(
    1, 
    'login_attempts', 
    'users', 
    NULL, 
    'login', 
    NULL, 
    NULL, 
    '190.12.34.56', 
    'Chrome', 
    'Ingreso exitoso al sistema'
);

-- 2. Logout de un administrador
CALL sp_log_audit(
    2, 
    'login_attempts', 
    'users', 
    NULL, 
    'logout', 
    NULL, 
    NULL, 
    '190.12.34.78', 
    'Firefox', 
    'Cierre de sesión seguro'
);

-- 3. Cambio de rol de usuario a supervisor
CALL sp_log_audit(
    1, 
    'role_changes', 
    'users', 
    5, 
    'update', 
    'user', 
    'supervisor', 
    NULL, 
    NULL, 
    'Promoción a supervisor por desempeño'
);

-- 4. Actualización de información de adulto mayor
CALL sp_log_audit(
    1, 
    'older_adult_updates', 
    'older_adults', 
    12, 
    'update', 
    '{"nombre": "Ana Pérez", "edad": 78}', 
    '{"nombre": "Ana Pérez", "edad": 79}', 
    NULL, 
    NULL, 
    'Actualización de edad tras cumpleaños'
);

-- 5. Acceso a función de medicamentos
CALL sp_log_audit(
    1, 
    'system_access', 
    'medications', 
    7, 
    'view', 
    NULL, 
    NULL, 
    NULL, 
    NULL, 
    'Visualizó historial de medicamentos del residente'
);

-- 6. Cambio en registro clínico
CALL sp_log_audit(
    2, 
    'clinical_record_changes', 
    'clinical_records', 
    9, 
    'update', 
    '{"presion": "120/80"}', 
    '{"presion": "130/85"}', 
    NULL, 
    NULL, 
    'Actualización de presión arterial por revisión diaria'
);
