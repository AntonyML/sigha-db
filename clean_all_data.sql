-- ================================================================================
-- Script para limpiar todos los datos de las tablas
-- Fecha: 2025-10-23
-- Descripción: Elimina todos los registros de todas las tablas respetando 
--              las dependencias de claves foráneas
-- ADVERTENCIA: Este script eliminará TODOS los datos. Usar con precaución.
-- ================================================================================

USE hogar_de_ancianos;

-- Deshabilitar verificación de claves foráneas temporalmente
SET FOREIGN_KEY_CHECKS = 0;

-- ####################################################################################
-- LIMPIEZA DE TABLAS - ORDEN CORRECTO RESPETANDO DEPENDENCIAS
-- ####################################################################################

-- Notificaciones
TRUNCATE TABLE notification_attachment;
TRUNCATE TABLE notifications;

-- Auditoría
TRUNCATE TABLE audit_reports;
TRUNCATE TABLE digital_record;

-- Historial médico y registros especializados
TRUNCATE TABLE medical_record;
TRUNCATE TABLE social_work_reports;
TRUNCATE TABLE psychology_sessions;
TRUNCATE TABLE physiotherapy_sessions;
TRUNCATE TABLE nursing_records;
TRUNCATE TABLE specialized_appointment;
TRUNCATE TABLE specialized_area;

-- Entradas y salidas
TRUNCATE TABLE entrances_exits;

-- Historial clínico y medicación
TRUNCATE TABLE clinical_medication;
TRUNCATE TABLE vaccines_and_clinical_history;
TRUNCATE TABLE clinical_history_and_conditions;
TRUNCATE TABLE clinical_history;
TRUNCATE TABLE vaccines;
TRUNCATE TABLE clinical_conditions;

-- Contactos de emergencia
TRUNCATE TABLE emergency_contacts;

-- Adultos mayores y relaciones
TRUNCATE TABLE older_adult_updates;
TRUNCATE TABLE older_adult_subprogram;
TRUNCATE TABLE older_adult;
TRUNCATE TABLE older_adult_family;

-- Programas
TRUNCATE TABLE sub_programs;
TRUNCATE TABLE programs;

-- Cambios de roles
TRUNCATE TABLE role_changes;

-- Autenticación y seguridad
TRUNCATE TABLE email_verification_tokens;
TRUNCATE TABLE password_reset_tokens;
TRUNCATE TABLE login_attempts;
TRUNCATE TABLE user_sessions;
TRUNCATE TABLE user_two_factor;

-- Usuarios
TRUNCATE TABLE users;

-- Roles
TRUNCATE TABLE roles;

-- Habilitar verificación de claves foráneas nuevamente
SET FOREIGN_KEY_CHECKS = 1;

-- ####################################################################################
-- REINSERTAR DATOS BÁSICOS NECESARIOS
-- ####################################################################################

-- Reinsertar roles básicos del sistema
INSERT INTO roles (r_name) VALUES 
    ('super admin'),
    ('admin'),
    ('director'),
    ('nurse'),
    ('physiotherapist'),
    ('psychologist'),
    ('social worker');

-- Reinsertar programas básicos
INSERT INTO programs (p_name) VALUES 
    ('Hogar larga instancia'), 
    ('Riesgo y abandono'), 
    ('Se cuidan');

-- Reinsertar subprogramas
INSERT INTO sub_programs (sp_name, id_program) VALUES 
    ('Condición socioeconómica', (SELECT id FROM programs WHERE p_name = 'Hogar larga instancia')),
    ('Medios propios', (SELECT id FROM programs WHERE p_name = 'Hogar larga instancia'));

-- Reinsertar condiciones clínicas
INSERT INTO clinical_conditions (cc_name) VALUES 
    ('HTA'), ('DBT'), ('Dislip'), ('IRC'), ('Cardio Isq.'), ('ACV'), ('Amputación'), 
    ('Tabaquismo'), ('Alcoholismo'), ('Parkinson'), ('Demencia'), ('Prostatismo'), 
    ('Incontinencia urinaria');

-- Reinsertar vacunas
INSERT INTO vaccines (v_name) VALUES 
    ('dT'), ('Hep B'), ('Gripe'), ('Neumococo');

-- Reinsertar áreas especializadas básicas
INSERT INTO specialized_area (sa_name, sa_description, sa_contact_email, sa_contact_phone, sa_is_active) VALUES 
    ('nursing', 'Área especializada en enfemería', 'enfermeria@example.com', '+506 23234348', 1),
    ('physiotherapy', 'Área especializada en fisioterapia', 'fisioterapia@example.com', '+506 23234349', 1),
    ('psychology', 'Área especializada en psicología', 'psicologia@example.com', '+506 23234347', 1),
    ('social_work', 'Área especializada en trabajo social', 'trabajosocial@example.com', '+506 23234346', 1);

-- ####################################################################################
-- VERIFICACIÓN Y REPORTE
-- ####################################################################################

SELECT '===============================================' as '';
SELECT 'LIMPIEZA COMPLETADA EXITOSAMENTE' as 'ESTADO';
SELECT '===============================================' as '';
SELECT '' as '';

SELECT 'CONTEO DE REGISTROS DESPUÉS DE LA LIMPIEZA:' as '';
SELECT 'Roles:', COUNT(*) as total FROM roles;
SELECT 'Usuarios:', COUNT(*) as total FROM users;
SELECT 'Programas:', COUNT(*) as total FROM programs;
SELECT 'Subprogramas:', COUNT(*) as total FROM sub_programs;
SELECT 'Condiciones Clínicas:', COUNT(*) as total FROM clinical_conditions;
SELECT 'Vacunas:', COUNT(*) as total FROM vaccines;
SELECT 'Áreas Especializadas:', COUNT(*) as total FROM specialized_area;
SELECT 'Adultos Mayores:', COUNT(*) as total FROM older_adult;
SELECT 'Familiares:', COUNT(*) as total FROM older_adult_family;
SELECT 'Historiales Clínicos:', COUNT(*) as total FROM clinical_history;
SELECT 'Citas Especializadas:', COUNT(*) as total FROM specialized_appointment;
SELECT 'Registros de Auditoría:', COUNT(*) as total FROM digital_record;
SELECT 'Notificaciones:', COUNT(*) as total FROM notifications;
SELECT 'Entradas/Salidas:', COUNT(*) as total FROM entrances_exits;
SELECT '' as '';
SELECT 'Todos los datos han sido limpiados.' as 'RESULTADO';
SELECT 'Se mantuvieron los datos básicos del sistema (roles, programas, condiciones, vacunas, áreas).' as 'NOTA';

-- ================================================================================
-- FIN DEL SCRIPT DE LIMPIEZA
-- ================================================================================