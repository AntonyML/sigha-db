-- ================================================================================
-- Script para actualizar la tabla audit_reports y agregar stored procedure
-- Fecha: 2025-10-23
-- Descripción: Actualiza la estructura de audit_reports y crea sp_log_audit
-- ================================================================================

USE hogar_de_ancianos;

-- ####################################################################################
-- ACTUALIZAR TABLA audit_reports
-- ####################################################################################

-- Eliminar la tabla anterior (si existe)
DROP TABLE IF EXISTS audit_reports;

-- Crear tabla de auditoría con nueva estructura (cambio de Tony)
CREATE TABLE audit_reports (
    id INT AUTO_INCREMENT PRIMARY KEY,
    ar_audit_number INT UNIQUE COMMENT 'Número secuencial único de auditoría',
    ar_type ENUM(
        'general_actions',
        'role_changes',
        'older_adult_updates',
        'system_access',
        'login_attempts',
        'password_resets',
        'clinical_record_changes',
        'notifications',
        'other'
    ) DEFAULT 'other' COMMENT 'Tipo de auditoría realizada',
    
    ar_entity_name VARCHAR(100) NULL COMMENT 'Nombre de la tabla o entidad afectada',
    ar_entity_id INT NULL COMMENT 'ID del registro afectado (si aplica)',
    ar_action ENUM('create', 'update', 'delete', 'view', 'login', 'logout', 'export', 'other') DEFAULT 'other' COMMENT 'Acción realizada',
    
    ar_old_value TEXT NULL COMMENT 'Valor anterior (si es actualización)',
    ar_new_value TEXT NULL COMMENT 'Valor nuevo (si es actualización)',
    ar_observations TEXT NULL COMMENT 'Observaciones adicionales o motivo de la acción',

    ar_start_date DATETIME NOT NULL COMMENT 'Inicio de auditoría o acción',
    ar_end_date DATETIME NULL COMMENT 'Fin de auditoría (si aplica)',
    ar_duration_seconds INT NULL COMMENT 'Duración de la acción en segundos (si aplica)',
    
    ar_ip_address VARCHAR(45) NULL COMMENT 'IP desde donde se realizó la acción',
    ar_user_agent TEXT NULL COMMENT 'Información del navegador o aplicación utilizada',

    create_at DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT 'Fecha de creación del registro de auditoría',
    
    id_generator INT NULL COMMENT 'Usuario que generó la acción',
    FOREIGN KEY (id_generator) REFERENCES users(id)
);

-- Índices para optimizar consultas frecuentes
CREATE INDEX idx_audit_type ON audit_reports(ar_type);
CREATE INDEX idx_audit_entity ON audit_reports(ar_entity_name, ar_entity_id);
CREATE INDEX idx_audit_user ON audit_reports(id_generator);
CREATE INDEX idx_audit_action ON audit_reports(ar_action);
CREATE INDEX idx_audit_create_at ON audit_reports(create_at);

-- ####################################################################################
-- STORED PROCEDURE sp_log_audit
-- ####################################################################################

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_log_audit$$

CREATE PROCEDURE sp_log_audit(
    IN p_user_id INT,
    IN p_type ENUM('general_actions','login_attempts','role_changes','older_adult_updates','system_access','clinical_record_changes','password_resets','notifications','other'),
    IN p_entity_name VARCHAR(100),
    IN p_entity_id INT,
    IN p_action ENUM('create', 'update', 'delete', 'view', 'login', 'logout', 'export', 'other'),
    IN p_old_value TEXT,
    IN p_new_value TEXT,
    IN p_ip VARCHAR(45),
    IN p_user_agent TEXT,
    IN p_observations TEXT
)
BEGIN
    DECLARE v_duration INT DEFAULT NULL;
    DECLARE v_end_date DATETIME DEFAULT NULL;
    
    -- Calcular duración y fecha de fin para logout
    IF p_type = 'login_attempts' AND p_action = 'logout' THEN
        SET v_end_date = NOW();
        
        -- Buscar el login más reciente del usuario para calcular duración
        SET v_duration = (
            SELECT TIMESTAMPDIFF(SECOND, ar_start_date, NOW())
            FROM audit_reports
            WHERE id_generator = p_user_id
              AND ar_type = 'login_attempts'
              AND ar_action = 'login'
              AND ar_end_date IS NULL
            ORDER BY ar_start_date DESC
            LIMIT 1
        );
    END IF;
    
    -- Insertar registro de auditoría
    INSERT INTO audit_reports (
        ar_type,
        ar_entity_name,
        ar_entity_id,
        ar_action,
        ar_old_value,
        ar_new_value,
        ar_start_date,
        ar_end_date,
        ar_duration_seconds,
        ar_ip_address,
        ar_user_agent,
        ar_observations,
        id_generator
    ) VALUES (
        p_type,
        p_entity_name,
        p_entity_id,
        p_action,
        p_old_value,
        p_new_value,
        NOW(),
        v_end_date,
        v_duration,
        p_ip,
        p_user_agent,
        p_observations,
        p_user_id
    );
END$$

DELIMITER ;

-- ####################################################################################
-- VERIFICACIÓN
-- ####################################################################################

SELECT '===============================================' as '';
SELECT 'ACTUALIZACIÓN COMPLETADA EXITOSAMENTE' as 'ESTADO';
SELECT '===============================================' as '';
SELECT '' as '';

-- Verificar estructura de la tabla
DESCRIBE audit_reports;

-- Verificar que el stored procedure existe
SELECT ROUTINE_NAME, ROUTINE_TYPE, ROUTINE_DEFINITION 
FROM INFORMATION_SCHEMA.ROUTINES 
WHERE ROUTINE_SCHEMA = 'hogar_de_ancianos' 
  AND ROUTINE_NAME = 'sp_log_audit';

-- ####################################################################################
-- EJEMPLOS DE USO
-- ####################################################################################

/*
-- Login exitoso
CALL sp_log_audit(
    1, 
    'login_attempts', 
    'users', 
    NULL, 
    'login', 
    NULL, 
    NULL, 
    '192.168.1.10', 
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0', 
    'Ingreso exitoso'
);

-- Logout
CALL sp_log_audit(
    1, 
    'login_attempts', 
    'users', 
    NULL, 
    'logout', 
    NULL, 
    NULL, 
    '192.168.1.10', 
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0', 
    'Cierre de sesión'
);

-- Cambio de rol
CALL sp_log_audit(
    1, 
    'role_changes', 
    'users', 
    2, 
    'update', 
    'user', 
    'admin', 
    NULL, 
    NULL, 
    'Cambio de rol a admin'
);

-- Actualización de adulto mayor
CALL sp_log_audit(
    1, 
    'older_adult_updates', 
    'older_adult', 
    5, 
    'update', 
    '{"age": 70}', 
    '{"age": 71}', 
    NULL, 
    NULL, 
    'Actualización de edad'
);

-- Acceso a función del sistema
CALL sp_log_audit(
    1, 
    'system_access', 
    'medication', 
    10, 
    'view', 
    NULL, 
    NULL, 
    NULL, 
    NULL, 
    'Visualizó registro de medicación'
);

-- Cambio en registro clínico
CALL sp_log_audit(
    1, 
    'clinical_record_changes', 
    'clinical_history', 
    12, 
    'update', 
    '{"blood_pressure": "120/80"}', 
    '{"blood_pressure": "130/85"}', 
    NULL, 
    NULL, 
    'Actualización de presión arterial'
);

-- Reseteo de contraseña
CALL sp_log_audit(
    1, 
    'password_resets', 
    'users', 
    5, 
    'update', 
    NULL, 
    NULL, 
    '192.168.1.20', 
    'Mozilla/5.0', 
    'Reseteo de contraseña solicitado'
);

-- Crear notificación
CALL sp_log_audit(
    1, 
    'notifications', 
    'notifications', 
    100, 
    'create', 
    NULL, 
    '{"title": "Recordatorio cita", "recipient": "user@example.com"}', 
    NULL, 
    NULL, 
    'Notificación de recordatorio de cita enviada'
);
*/

-- ================================================================================
-- FIN DEL SCRIPT
-- ================================================================================