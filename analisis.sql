DROP DATABASE IF EXISTS hogar_de_ancianos;
CREATE DATABASE hogar_de_ancianos;
USE hogar_de_ancianos;

-- ####################################################################################

-- Tabla de roles
CREATE TABLE roles (
    id INT AUTO_INCREMENT PRIMARY KEY,
    r_name ENUM('super admin', 'admin', 'director', 'nurse', 'physiotherapist', 'psychologist', 'social worker', 'not specified') DEFAULT 'not specified'
);

CREATE INDEX idx_role_name ON roles(r_name);

-- Tabla de usuarios
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    u_identification VARCHAR(20) NOT NULL UNIQUE,
    u_name VARCHAR(50) NOT NULL,
    u_f_last_name VARCHAR(50) NOT NULL,
    u_s_last_name VARCHAR(50) NULL,
    u_email VARCHAR(256) UNIQUE NOT NULL,
    u_email_verified BOOLEAN DEFAULT FALSE,
    u_password VARCHAR(255) NOT NULL,
    u_is_active BOOLEAN DEFAULT TRUE,
    create_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    role_id INT,
    FOREIGN KEY (role_id) REFERENCES roles(id)
);

CREATE INDEX idx_user_email ON users(u_email);
CREATE INDEX idx_user_identification ON users(u_identification);

-- ####################################################################################

-- Tabla para almacenar información de 2FA de los usuarios
CREATE TABLE user_two_factor (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    tfa_secret VARCHAR(255) NOT NULL,              -- Secret para TOTP
    tfa_enabled BOOLEAN DEFAULT FALSE,              -- Si 2FA está activado
    tfa_backup_codes TEXT NULL,                     -- Códigos de respaldo (JSON array)
    tfa_last_used DATETIME NULL,                    -- Última vez que se usó 2FA
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Tabla para almacenar sesiones JWT activas
CREATE TABLE user_sessions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    session_token VARCHAR(500) NOT NULL,    -- JWT token hash
    refresh_token VARCHAR(500) NULL,                -- Refresh token hash
    ip_address VARCHAR(45) NULL,                    -- IPv4 o IPv6
    user_agent TEXT NULL,                           -- Información del navegador/app
    is_active BOOLEAN DEFAULT TRUE,
    expires_at DATETIME NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_activity DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_user_sessions ON user_sessions(user_id, is_active);
CREATE INDEX idx_session_token ON user_sessions(session_token);
CREATE INDEX idx_expires_at ON user_sessions(expires_at);

-- Tabla para registrar intentos de login (seguridad)
CREATE TABLE login_attempts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NULL,                               -- NULL si el usuario no existe
    email VARCHAR(256) NOT NULL,
    ip_address VARCHAR(45) NULL,
    attempt_successful BOOLEAN DEFAULT FALSE,
    failure_reason VARCHAR(100) NULL,               -- 'invalid_password', 'invalid_2fa', 'user_not_found', etc.
    attempted_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
);

CREATE INDEX idx_login_attempts ON login_attempts(email, attempted_at);
CREATE INDEX idx_ip_attempts ON login_attempts(ip_address, attempted_at);

-- Tabla para tokens de recuperación de contraseña
CREATE TABLE password_reset_tokens (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    token VARCHAR(255) NOT NULL,
    expires_at DATETIME NOT NULL,
    used BOOLEAN DEFAULT FALSE,
    used_at DATETIME NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_token ON password_reset_tokens(token);
CREATE INDEX idx_expires ON password_reset_tokens(expires_at, used);

-- Tabla para tokens de verificación de email
CREATE TABLE email_verification_tokens (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    token VARCHAR(255) NOT NULL UNIQUE,
    expires_at DATETIME NOT NULL,
    verified BOOLEAN DEFAULT FALSE,
    verified_at DATETIME NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_token ON email_verification_tokens(token);
CREATE INDEX idx_expires ON email_verification_tokens(expires_at, verified);

-- ####################################################################################

-- Tabla para guardar los cambios de roles en usuarios
CREATE TABLE role_changes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    rc_old_role VARCHAR(50),
    rc_new_role VARCHAR(50),
    changed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    id_user INT NOT NULL, 	      	-- Usuario afectado
    changed_by INT NOT NULL,     	-- Admin que hizo el cambio
    FOREIGN KEY (id_user) REFERENCES users(id),
    FOREIGN KEY (changed_by) REFERENCES users(id)
);

CREATE INDEX idx_rolechanges_user ON users(id);
CREATE INDEX idx_rolechanges_changedby ON users(id);

-- ####################################################################################

-- Tabla para programas del hogar
CREATE TABLE programs (
	id INT AUTO_INCREMENT PRIMARY KEY,
    p_name VARCHAR(300) NOT NULL,
    create_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_program_name ON programs(p_name);

-- Tabla para agregar participantes a un programa
CREATE TABLE sub_programs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    sp_name VARCHAR(50) NOT NULL,
    id_program INT,
    FOREIGN KEY (id_program) REFERENCES programs(id) ON DELETE CASCADE
);

CREATE INDEX idx_subprogram_name ON sub_programs(sp_name);

INSERT INTO programs (p_name) VALUES ('Hogar larga instancia'), ('Riesgo y abandono'), ('Se cuidan');
INSERT INTO sub_programs (sp_name, id_program) VALUES ('Condición socioeconómica', (SELECT id FROM programs WHERE p_name = 'Hogar larga instancia'));
INSERT INTO sub_programs (sp_name, id_program) VALUES ('Medios propios', (SELECT id FROM programs WHERE p_name = 'Hogar larga instancia'));

-- ####################################################################################

-- Tabla para familiares de un paciente
CREATE TABLE older_adult_family (
	id INT AUTO_INCREMENT PRIMARY KEY,
	pf_identification VARCHAR(20) NOT NULL,
    pf_name VARCHAR(50) NOT NULL,
    pf_f_last_name VARCHAR(50) NOT NULL,
    pf_s_last_name VARCHAR(50) NOT NULL,
    pf_phone_number VARCHAR(20) NULL,
    pf_email VARCHAR(256) NULL,
    pf_kinship  ENUM(
		'son', 'daughter', 'grandson', 'granddaughter', 'brother', 'sister',
        'nephew', 'niece', 'husband', 'wife', 'legal guardian', 'other', 'not specified'
	) NOT NULL DEFAULT 'not specified',
    create_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_adult_family_identification ON older_adult_family(pf_identification);
CREATE INDEX idx_adult_family_email ON older_adult_family(pf_email);

-- Tabla de adultos mayores (SON PACIENTES Y DE ACÁ SALE EL EXPEDIENTE VIRTUAL)
CREATE TABLE older_adult (
    id INT AUTO_INCREMENT PRIMARY KEY,
    oa_identification VARCHAR(20) NOT NULL UNIQUE,
    oa_name VARCHAR(50) NOT NULL,
    oa_f_last_name VARCHAR(50) NOT NULL,
    oa_s_last_name VARCHAR(50) NULL,
    oa_birthdate DATE,
    oa_marital_status ENUM('single', 'married', 'divorced', 'widowed', 'common law union', 'separated', 'not specified') DEFAULT 'not specified',
    oa_dwelling TEXT NULL,
    oa_years_schooling ENUM(
		'no schooling', 'incomplete primary', 'complete primary', 'incomplete secondary',
        'complete secondary', 'technical degree', 'incomplete university', 'complete university', 
        'postgraduate', 'not specified'
	) NOT NULL DEFAULT 'not specified',
    oa_previous_work VARCHAR(300) NOT NULL,
    oa_is_retired BOOLEAN NOT NULL DEFAULT FALSE,		-- ¿Está jubilado?
    oa_has_pension BOOLEAN NOT NULL DEFAULT FALSE,		-- ¿Tiene pensión?
    oa_other BOOLEAN NOT NULL DEFAULT FALSE, 	  		-- ¿Otro?
    oa_other_description VARCHAR(300) NULL,		  		-- Descripción para atributo anterior si es = TRUE
    oa_area_of_origin VARCHAR(300) NULL,
	oa_children_count TINYINT UNSIGNED DEFAULT 0,
    oa_status ENUM('alive', 'dead') DEFAULT 'alive',
    oa_death_date DATE NULL, 					  		-- En caso de que haya muerto, guardar fecha
    oa_economic_income DECIMAL(10, 2) NULL,	  		-- Ingreso económico del hogar (colones)
    oa_phone_numner VARCHAR(20) NULL,
    oa_email VARCHAR(256) NULL,
    oa_profile_photo_url VARCHAR(255) NULL,
    -- adicionales
	oa_gender ENUM('male', 'female', 'not specified') DEFAULT 'not specified',
	oa_blood_type ENUM('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'UNKNOWN') DEFAULT 'UNKNOWN',
	create_at DATETIME DEFAULT CURRENT_TIMESTAMP,
	-- llaves foráneas
    id_program INT,
    id_family INT,
    FOREIGN KEY (id_program) REFERENCES programs(id) ON DELETE SET NULL,
    FOREIGN KEY (id_family) REFERENCES older_adult_family(id) ON DELETE SET NULL
);

CREATE INDEX idx_olderadult_identification ON older_adult(oa_identification);
CREATE INDEX idx_olderadult_name ON older_adult(oa_name);
CREATE INDEX idx_olderadult_f_lastname ON older_adult(oa_f_last_name);
CREATE INDEX idx_olderadult_email ON older_adult(oa_email);
CREATE INDEX idx_olderadult_birthdate ON older_adult(oa_birthdate);

-- Tabla para asociar un subprograma a un adulto mayor
-- SOLO SE USA CUANDO EL PROGRAMA ASIGNADO ES "HOGAR LARGA INSTANCIA"
CREATE TABLE older_adult_subprogram (
	id_older_adult INT NOT NULL,
    id_sub_program INT NOT NULL,
    FOREIGN KEY (id_older_adult) REFERENCES older_adult(id) ON DELETE CASCADE,
	FOREIGN KEY (id_sub_program) REFERENCES sub_programs(id) ON DELETE CASCADE
);

-- Tabla de números de emergencia para adulto mayor cuando es paciente
CREATE TABLE emergency_contacts (
	id INT AUTO_INCREMENT PRIMARY KEY,
    en_phone_number VARCHAR(20) NOT NULL,
	create_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    id_older_adult INT,
    FOREIGN KEY (id_older_adult) REFERENCES older_adult(id) ON DELETE CASCADE
);

CREATE INDEX idx_emergency_number ON emergency_contacts(en_phone_number);

-- ####################################################################################

-- Tabla para guardar los cambios en datos de adultos mayores
CREATE TABLE older_adult_updates (
    id INT AUTO_INCREMENT PRIMARY KEY,
    oau_field_changed VARCHAR(100) NOT NULL,
    oau_old_value TEXT NULL,
    oau_new_value TEXT NULL,
    changed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
	id_older_adult INT NOT NULL,
    changed_by INT NOT NULL,
    FOREIGN KEY (id_older_adult) REFERENCES older_adult(id),
    FOREIGN KEY (changed_by) REFERENCES users(id)
);

CREATE INDEX idx_adultupdates_adult ON older_adult_updates(id_older_adult);
CREATE INDEX idx_adultupdates_field ON older_adult_updates(oau_field_changed);

-- ####################################################################################

-- Tabla de padecimeintos
CREATE TABLE clinical_conditions (
	id INT AUTO_INCREMENT PRIMARY KEY,
	cc_name VARCHAR(55) NOT NULL
);
-- AGREGAR INSERT DE CONDICIONES
CREATE INDEX idx_clinicalcondition_name ON clinical_conditions(cc_name);

INSERT INTO clinical_conditions (cc_name) VALUES 
	('HTA'), ('DBT'), ('Dislip'), ('IRC'), ('Cardio Isq.'), ('ACV'), ('Amputación'), 
    ('Tabaquismo'), ('Alcoholismo'), ('Parkinson'), ('Demencia'), ('Prostatismo'), ('Incontinencia urinaria')
;

-- Tabla de tipos de vacunas
CREATE TABLE vaccines (
	id INT AUTO_INCREMENT PRIMARY KEY,
    v_name VARCHAR(80) NOT NULL
);
-- AGREGAR INSERT DE VACUNAS
CREATE INDEX idx_vaccines_name ON vaccines(v_name);

INSERT INTO vaccines (v_name) VALUES ('dT'), ('Hep B'), ('Gripe'), ('Neumococo');

-- Tabla de antecedentes clínicos de un paciente
CREATE TABLE clinical_history (
	id INT AUTO_INCREMENT PRIMARY KEY,
    ch_frequent_falls BOOLEAN NOT NULL DEFAULT FALSE,
    ch_weight DECIMAL(5,2) NULL,        	-- Peso en kg
    ch_height DECIMAL(4,2) NULL,        	-- Altura en metros
    ch_imc DECIMAL(4,1) NULL,           	-- Indice de masa corporal
    ch_blood_pressure VARCHAR(7) NULL,   	-- Tensión arterial ('120/80')
    ch_neoplasms BOOLEAN NOT NULL DEFAULT FALSE,
    ch_neoplasms_description VARCHAR(300) NULL,				-- Solo en caso de que sí hay tenido neoplasias
    ch_observations TEXT NULL,
    ch_rcvg ENUM('< 10%', 'e /10y20%', 'e /20y30%', 'e /40y40%', '> 40%', 'UNKNOWN') DEFAULT 'UNKNOWN',		-- Riesgo cardiovascular global
    ch_vision_problems BOOLEAN NOT NULL DEFAULT FALSE,		-- TRUE = tiene problemas de visión, FALSE = no tiene problemas
    ch_vision_hearing BOOLEAN NOT NULL DEFAULT FALSE,		-- TRUE = tiene problemas de audición, FALSE = no tiene problemas
	create_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    id_older_adult INT NULL,
    FOREIGN KEY (id_older_adult) REFERENCES older_adult(id)
);

CREATE INDEX idx_clinicalhistory_createat ON clinical_history(create_at);

-- Tabla relación de clinical_conditions y clinical_history
CREATE TABLE clinical_history_and_conditions (
	id_c_condition INT,
    id_c_history INT,
    FOREIGN KEY (id_c_condition) REFERENCES clinical_conditions(id) ON DELETE CASCADE,
    FOREIGN KEY (id_c_history) REFERENCES clinical_history(id) ON DELETE CASCADE
);

-- Tabla relación de vaccines y clinical_history
CREATE TABLE vaccines_and_clinical_history (
	id_vaccine INT,
    id_c_history INT,
    FOREIGN key (id_vaccine) REFERENCES vaccines(id) ON DELETE CASCADE,
	FOREIGN key (id_c_history) REFERENCES clinical_history(id) ON DELETE CASCADE
);

-- Tabla de medicación
CREATE TABLE clinical_medication (
	id INT AUTO_INCREMENT PRIMARY KEY,
    m_medication VARCHAR(500) NOT NULL,
    m_dosage VARCHAR(200) NOT NULL,
    m_treatment_type ENUM('temporary', 'chronic', 'preventive', 'other') NOT NULL DEFAULT 'other',
    id_clinical_history INT,
    FOREIGN KEY (id_clinical_history) REFERENCES clinical_history(id) ON DELETE CASCADE
);

CREATE INDEX idx_clinicalmedication_medication ON clinical_medication(m_medication);

-- ####################################################################################

-- Tabla para entradas y salidas al hogar
CREATE TABLE entrances_exits (
	id INT AUTO_INCREMENT PRIMARY KEY,
	ee_type ENUM('employee', 'older adult', 'visitor', 'volunteer', 'vehicle', 'other') DEFAULT 'other',
    ee_access_type ENUM('entrance', 'exit') NOT NULL,
    ee_identification VARCHAR(20) NULL,
    ee_name VARCHAR(50) NULL,
    ee_f_last_name VARCHAR(50) NULL,
    ee_s_last_name VARCHAR(50) NULL,
    ee_datetime_entrance DATETIME NULL,
    ee_datetime_exit DATETIME NULL,
    ee_close BOOLEAN NOT NULL DEFAULT FALSE,					-- FALSE = aún dentro o aún fuera, TRUE = ciclo cerrado
    ee_observations TEXT NULL,
	create_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_entrancesexits_type ON entrances_exits(ee_type);
CREATE INDEX idx_entrancesexits_identification ON entrances_exits(ee_identification);
CREATE INDEX idx_entrancesexits_name ON entrances_exits(ee_name);

-- ####################################################################################

-- Tabla de áreas especializadas del hogar
CREATE TABLE specialized_area (
    id INT AUTO_INCREMENT PRIMARY KEY,
    sa_name ENUM('nursing', 'physiotherapy', 'psychology', 'social_work', 'not specified') NOT NULL DEFAULT 'not specified',
    sa_description TEXT NULL,                             -- Descripción general del área
    sa_contact_email VARCHAR(256) NULL,
    sa_contact_phone VARCHAR(20) NULL,
    sa_is_active BOOLEAN DEFAULT TRUE,                    -- Por si el área deja de operar
    create_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    id_manager INT,
    FOREIGN KEY (id_manager) REFERENCES users(id) ON DELETE SET NULL
);

CREATE INDEX idx_area_name ON specialized_area(sa_name);
CREATE INDEX idx_area_email ON specialized_area(sa_contact_email);

INSERT INTO specialized_area (sa_name, sa_description, sa_contact_email, sa_contact_phone, sa_is_active) VALUES 
('nursing', 'Área especializada en enfemería', 'enfermeria@example.com', '+506 23234348', 1),
('physiotherapy', 'Área especializada en fisioterapia', 'fisioterapia@example.com', '+506 23234349', 1),
('psychology', 'Área especializada en psicología', 'psicologia@example.com', '+506 23234347', 1),
('social_work', 'Área especializada en trabajo social', 'trabajosocial@example.com', '+506 23234346', 1);

-- Tabla de citas y atenciones en áreas especializadas
CREATE TABLE specialized_appointment (
    id INT AUTO_INCREMENT PRIMARY KEY,
    sa_appointment_date DATETIME NOT NULL,
    sa_appointment_type ENUM('checkup', 'evaluation', 'therapy', 'follow_up', 'emergency') DEFAULT 'checkup',
    sa_priority ENUM('low', 'medium', 'high', 'urgent') DEFAULT 'medium',
    sa_status ENUM('scheduled', 'in_progress', 'completed', 'cancelled', 'rescheduled') DEFAULT 'scheduled',
    sa_notes TEXT NULL,
    sa_observations TEXT NULL,
    sa_duration_minutes SMALLINT UNSIGNED NULL,          -- Duración estimada o real
    sa_next_appointment DATETIME NULL,                   -- Fecha para control futuro (VALIDAR FUERTE)
    create_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    id_area INT NOT NULL,
    id_patient INT NOT NULL,
    id_staff INT NOT NULL,
    FOREIGN KEY (id_area) REFERENCES specialized_area(id) ON DELETE CASCADE,
    FOREIGN KEY (id_patient) REFERENCES older_adult(id) ON DELETE CASCADE,
    FOREIGN KEY (id_staff) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_appointment_date ON specialized_appointment(sa_appointment_date);
CREATE INDEX idx_appointment_priority ON specialized_appointment(sa_priority);
CREATE INDEX idx_appointment_createat ON specialized_appointment(create_at);

-- ####################################################################################

-- Tabla para registrar datos de cita con enfermería
CREATE TABLE nursing_records (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nr_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    nr_temperature DECIMAL(4,1) NULL,
    nr_blood_pressure VARCHAR(7) NULL,			-- 120/80
    nr_heart_rate SMALLINT UNSIGNED NULL,		-- Pulso
    nr_pain_level TINYINT UNSIGNED NULL,		-- Escala del 0 - 10
    nr_mobility ENUM('independent', 'assisted', 'bedridden') DEFAULT 'independent',
    nr_appetite ENUM('good', 'regular', 'poor') DEFAULT 'regular',
    nr_sleep_quality ENUM('good', 'regular', 'poor') DEFAULT 'regular',
    nr_notes TEXT NULL,
    create_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    id_appointment INT,
    FOREIGN KEY (id_appointment) REFERENCES specialized_appointment(id) ON DELETE CASCADE
);

CREATE INDEX idx_nursing_createat ON nursing_records(create_at);

-- Tabla para guardar datos de cita con fisioterapia
CREATE TABLE physiotherapy_sessions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    ps_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    ps_type ENUM('evaluation', 'therapy', 'follow_up') DEFAULT 'therapy',
    ps_mobility_level ENUM('high', 'moderate', 'low', 'none') DEFAULT 'moderate',
    ps_pain_level TINYINT UNSIGNED NULL,		-- Escala del 0 - 10
    ps_treatment_description TEXT,
    ps_exercise_plan TEXT,
    ps_progress_notes TEXT,    
    create_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    id_appointment INT NOT NULL,
    FOREIGN KEY (id_appointment) REFERENCES specialized_appointment(id) ON DELETE CASCADE
);

CREATE INDEX idx_physiotherapy_createat ON physiotherapy_sessions(create_at);
CREATE INDEX idx_physiotherapy_type ON physiotherapy_sessions(ps_type);

-- Tabla para guardar datos de cita con psicólogo
CREATE TABLE psychology_sessions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    psy_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    psy_session_type ENUM('evaluation', 'therapy', 'follow_up', 'group therapy') DEFAULT 'evaluation',
    psy_mood ENUM('stable', 'anxious', 'depressed', 'irritable', 'other') DEFAULT 'stable',
    psy_cognitive_status ENUM('normal', 'mild impairment', 'moderate impairment', 'severe impairment') DEFAULT 'normal',
    psy_observations TEXT,
    psy_therapy_goal TEXT,
    psy_progress TEXT,
    create_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    id_appointment INT,
    FOREIGN KEY (id_appointment) REFERENCES specialized_appointment(id) ON DELETE CASCADE
);

CREATE INDEX idx_psychology_createat ON psychology_sessions(create_at);
CREATE INDEX idx_psychology_type ON psychology_sessions(psy_session_type);

-- Tabla para guardar datos de trabajo social
CREATE TABLE social_work_reports (
    id INT AUTO_INCREMENT PRIMARY KEY,
    sw_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    sw_visit_type ENUM('home visit', 'institutional visit', 'interview', 'follow_up') DEFAULT 'interview',
    sw_family_relationship TEXT NULL,
    sw_economic_assessment TEXT NULL,
    sw_social_support TEXT NULL,
    sw_observations TEXT,
    sw_recommendations TEXT,
    create_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    id_appointment INT,
    FOREIGN KEY (id_appointment) REFERENCES specialized_appointment(id) ON DELETE CASCADE
);

CREATE INDEX idx_socialwork_createat ON social_work_reports(create_at);
CREATE INDEX idx_socialwork_date ON social_work_reports(sw_date);

-- ####################################################################################

-- Tabla de historial médico general (registro cronológico)
CREATE TABLE medical_record (
    id INT AUTO_INCREMENT PRIMARY KEY,
    mr_record_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    mr_summary TEXT NOT NULL,                                   -- Resumen clínico (motivo, evolución, diagnóstico)
    mr_diagnosis TEXT NULL,                                     -- Diagnóstico general o provisional
    mr_treatment TEXT NULL,                                     -- Tratamiento aplicado o recomendado
    mr_observations TEXT NULL,                                  -- Observaciones generales o inter-área
    mr_origin_area VARCHAR(60) NOT NULL,                        -- Área que generó el registro (ej. enfermería, psicología)
    mr_signed_by VARCHAR(150) NULL,                             -- Nombre del profesional o firma digital
    create_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    id_older_adult INT NOT NULL,
    id_appointment INT NULL,
    id_staff INT NULL,
    FOREIGN KEY (id_older_adult) REFERENCES older_adult(id) ON DELETE CASCADE,
    FOREIGN KEY (id_appointment) REFERENCES specialized_appointment(id),
    FOREIGN KEY (id_staff) REFERENCES users(id) ON DELETE SET NULL
);

CREATE INDEX idx_medicalrecord_createat ON medical_record(create_at);
CREATE INDEX idx_medicalrecord_date ON medical_record(mr_record_date);

-- ####################################################################################

-- Tabla de registros de usuarios
CREATE TABLE digital_record (
    id INT AUTO_INCREMENT PRIMARY KEY,
    dr_user_id INT NOT NULL,
    dr_action ENUM('login', 'logout', 'create', 'update', 'delete', 'view', 'export', 'other') DEFAULT 'other',
    dr_table_name VARCHAR(100) NULL,        -- Ej. 'older_adult', 'programs', 'medical_record'
    dr_record_id INT NULL,                  -- ID del registro afectado
    dr_description TEXT NULL,               -- Ej. "Eliminó paciente con ID 32"
    dr_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (dr_user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_digital_name ON digital_record(dr_table_name);
CREATE INDEX idx_digital_action ON digital_record(dr_action);

-- Tabla de auditoría (conteo de auditorías generadas) (cambio de tony)
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

-- Tabla para notificaciones y alertas
CREATE TABLE notifications (
    id INT AUTO_INCREMENT PRIMARY KEY,
    n_title VARCHAR(150) NOT NULL,
    n_message TEXT NOT NULL,
    n_send_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    n_sent BOOLEAN DEFAULT FALSE,
    create_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    id_sender INT NOT NULL,
    FOREIGN KEY (id_sender) REFERENCES users(id)
);

CREATE INDEX idx_notification_title ON notifications(n_title);
CREATE INDEX idx_notification_date ON notifications(n_send_date);
CREATE INDEX idx_notification_createat ON notifications(create_at);

-- Tabla que guarda las rutas de los archivos adjuntos de una notificación
CREATE TABLE notification_attachment (
	id INT AUTO_INCREMENT PRIMARY KEY,
    na_file_name VARCHAR(150) NOT NULL,
    na_file_path VARCHAR(255) NOT NULL,
    na_file_mime_type VARCHAR(100) NOT NULL, 	-- Guarda el tipo del archivo (se valida en backend)
    na_file_size_kb INT NOT NULL,			 	-- Tamaño en KB del archivo (no mayor a 5 MB)
    id_notification INT NOT NULL,
    FOREIGN KEY (id_notification) REFERENCES notifications(id)
);



-- IMPORTANTE: ACÁ SE PUEDEN ELIMINAR LOS REGISTROS CON "ON DELETE CASCADE", PERO PRIMERO HAY QUE TOMAR LA RUTA DONDE 
-- ESTÁN LOS ARCHIVOS Y ELIMINARLOS PARA QUE NO QUITEN ESPACIO, LUEGO SE PUEDEN BORRAR LOS REGISTROS DE ACÁ

CREATE INDEX idx_attachment_name ON notification_attachment(na_file_name);
CREATE INDEX idx_attachment_path ON notification_attachment(na_file_path);

-- $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

-- SP para limpiar sesiones expiradas (ejecutar periódicamente)
DELIMITER $$
CREATE PROCEDURE clean_expired_sessions()
BEGIN
    UPDATE user_sessions 
    SET is_active = FALSE 
    WHERE expires_at < NOW() AND is_active = TRUE;
    
    DELETE FROM user_sessions 
    WHERE is_active = FALSE 
    AND last_activity < DATE_SUB(NOW(), INTERVAL 30 DAY);
END$$
DELIMITER ;

DELIMITER $$
CREATE PROCEDURE clean_expired_tokens()
BEGIN
    DELETE FROM password_reset_tokens 
    WHERE expires_at < NOW() AND used = FALSE;
    
    DELETE FROM email_verification_tokens 
    WHERE expires_at < NOW() AND verified = FALSE;
END$$
DELIMITER ;

-- SP para obtener estadísticas de intentos de login fallidos
DELIMITER $$
CREATE PROCEDURE get_failed_login_stats(
    IN time_window_hours INT
)
BEGIN
    SELECT 
        email,
        ip_address,
        COUNT(*) as failed_attempts,
        MAX(attempted_at) as last_attempt,
        failure_reason
    FROM login_attempts
    WHERE 
        attempt_successful = FALSE 
        AND attempted_at > DATE_SUB(NOW(), INTERVAL time_window_hours HOUR)
    GROUP BY email, ip_address, failure_reason
    HAVING failed_attempts >= 3
    ORDER BY failed_attempts DESC, last_attempt DESC;
END$$
DELIMITER ;

-- SP crea la ficha virtual de un adulto mayor (registra en las tablas correspondientes)
DELIMITER $$
CREATE PROCEDURE CreateVirtualFile(
    IN p_oa_identification VARCHAR(20),
    IN p_oa_name VARCHAR(50),
    IN p_oa_f_last_name VARCHAR(50),
    IN p_oa_s_last_name VARCHAR(50),
    IN p_oa_birthdate DATE,
    IN p_oa_marital_status VARCHAR(20),
    IN p_oa_dwelling TEXT,
    IN p_oa_years_schooling VARCHAR(50),
    IN p_oa_previous_work VARCHAR(300),
    IN p_oa_is_retired BOOLEAN,
    IN p_oa_has_pension BOOLEAN,
    IN p_oa_other BOOLEAN,
    IN p_oa_other_description VARCHAR(300),
    IN p_oa_area_of_origin VARCHAR(300),
    IN p_oa_children_count TINYINT,
    IN p_oa_status VARCHAR(10),
    IN p_oa_death_date DATE,
    IN p_oa_economic_income DECIMAL(10,2),
    IN p_oa_phone_numner VARCHAR(20),
    IN p_oa_email VARCHAR(256),
    IN p_oa_profile_photo_url VARCHAR(255),
    IN p_oa_gender VARCHAR(15),
    IN p_oa_blood_type VARCHAR(10),
    IN p_program_id INT,
    
    IN p_pf_identification VARCHAR(20),
    IN p_pf_name VARCHAR(50),
    IN p_pf_f_last_name VARCHAR(50),
    IN p_pf_s_last_name VARCHAR(50),
    IN p_pf_phone_number VARCHAR(20),
    IN p_pf_email VARCHAR(256),
    IN p_pf_kinship VARCHAR(20),
    
    IN p_ch_frequent_falls BOOLEAN,
    IN p_ch_weight DECIMAL(5,2),
    IN p_ch_height DECIMAL(4,2),
    IN p_ch_imc DECIMAL(4,1),
    IN p_ch_blood_pressure VARCHAR(7),
    IN p_ch_neoplasms BOOLEAN,
    IN p_ch_neoplasms_description VARCHAR(300),
    IN p_ch_observations TEXT,
    IN p_ch_rcvg VARCHAR(20),
    IN p_ch_vision_problems BOOLEAN,
    IN p_ch_vision_hearing BOOLEAN,
    
    IN p_clinical_conditions_ids VARCHAR(500),
    IN p_vaccines_ids VARCHAR(500),
    IN p_subprograms_ids VARCHAR(500),
    
    IN p_medications_json TEXT
)
BEGIN
    DECLARE v_older_adult_id INT DEFAULT NULL;
    DECLARE v_family_id INT DEFAULT NULL;
    DECLARE v_clinical_history_id INT DEFAULT NULL;
    DECLARE v_error_message VARCHAR(500);
    DECLARE v_counter INT DEFAULT 0;
    DECLARE v_current_id VARCHAR(10);
    DECLARE v_pos INT DEFAULT 0;
    DECLARE v_length INT DEFAULT 0;
    DECLARE v_medications_count INT DEFAULT 0;
    
    DECLARE v_conditions_list VARCHAR(500);
    DECLARE v_vaccines_list VARCHAR(500);
    DECLARE v_subprograms_list VARCHAR(500);
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1
            v_error_message = MESSAGE_TEXT;
        SELECT CONCAT('Error: ', v_error_message) as error_message;
    END;
    
    START TRANSACTION;
    
    IF p_oa_identification IS NULL OR p_oa_identification = '' THEN
        SET v_error_message = 'La identificación del adulto mayor es requerida';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_error_message;
    END IF;
    
    IF p_oa_name IS NULL OR p_oa_name = '' THEN
        SET v_error_message = 'El nombre del adulto mayor es requerido';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_error_message;
    END IF;
    
    IF p_oa_f_last_name IS NULL OR p_oa_f_last_name = '' THEN
        SET v_error_message = 'El primer apellido del adulto mayor es requerido';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_error_message;
    END IF;
    
    IF EXISTS (SELECT 1 FROM older_adult WHERE oa_identification = p_oa_identification) THEN
        SET v_error_message = CONCAT('Ya existe un adulto mayor con la identificación: ', p_oa_identification);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_error_message;
    END IF;
    
    IF p_program_id IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM programs WHERE id = p_program_id) THEN
            SET v_error_message = CONCAT('El programa con ID ', p_program_id, ' no existe');
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_error_message;
        END IF;
    END IF;
    
    IF p_pf_identification IS NULL OR p_pf_identification = '' THEN
        SET v_error_message = 'La identificación del familiar es requerida';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_error_message;
    END IF;
    
    IF p_pf_name IS NULL OR p_pf_name = '' THEN
        SET v_error_message = 'El nombre del familiar es requerido';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_error_message;
    END IF;
    
    IF p_pf_email IS NULL OR p_pf_email = '' THEN
        SET v_error_message = 'El email del familiar es requerido';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_error_message;
    END IF;
    
    INSERT INTO older_adult_family (
        pf_identification, pf_name, pf_f_last_name, pf_s_last_name,
        pf_phone_number, pf_email, pf_kinship
    ) VALUES (
        p_pf_identification, p_pf_name, p_pf_f_last_name, p_pf_s_last_name,
        p_pf_phone_number, p_pf_email, p_pf_kinship
    );
    
    SET v_family_id = LAST_INSERT_ID();
    
    INSERT INTO older_adult (
        oa_identification, oa_name, oa_f_last_name, oa_s_last_name, oa_birthdate,
        oa_marital_status, oa_dwelling, oa_years_schooling, oa_previous_work,
        oa_is_retired, oa_has_pension, oa_other, oa_other_description,
        oa_area_of_origin, oa_children_count, oa_status, oa_death_date,
        oa_economic_income, oa_phone_numner, oa_email, oa_profile_photo_url,
        oa_gender, oa_blood_type, id_program, id_family
    ) VALUES (
        p_oa_identification, p_oa_name, p_oa_f_last_name, p_oa_s_last_name, p_oa_birthdate,
        p_oa_marital_status, p_oa_dwelling, p_oa_years_schooling, p_oa_previous_work,
        p_oa_is_retired, p_oa_has_pension, p_oa_other, p_oa_other_description,
        p_oa_area_of_origin, p_oa_children_count, p_oa_status, p_oa_death_date,
        p_oa_economic_income, p_oa_phone_numner, p_oa_email, p_oa_profile_photo_url,
        p_oa_gender, p_oa_blood_type, p_program_id, v_family_id
    );
    
    SET v_older_adult_id = LAST_INSERT_ID();
    
    INSERT INTO clinical_history (
        ch_frequent_falls, ch_weight, ch_height, ch_imc, ch_blood_pressure,
        ch_neoplasms, ch_neoplasms_description, ch_observations, ch_rcvg,
        ch_vision_problems, ch_vision_hearing
    ) VALUES (
        p_ch_frequent_falls, p_ch_weight, p_ch_height, p_ch_imc, p_ch_blood_pressure,
        p_ch_neoplasms, p_ch_neoplasms_description, p_ch_observations, p_ch_rcvg,
        p_ch_vision_problems, p_ch_vision_hearing
    );
    
    SET v_clinical_history_id = LAST_INSERT_ID();
    
    IF p_clinical_conditions_ids IS NOT NULL AND p_clinical_conditions_ids != '' THEN
        SET v_conditions_list = CONCAT(p_clinical_conditions_ids, ',');
        SET v_pos = 1;
        
        WHILE v_pos > 0 DO
            SET v_pos = LOCATE(',', v_conditions_list);
            IF v_pos > 0 THEN
                SET v_current_id = LEFT(v_conditions_list, v_pos - 1);
                SET v_conditions_list = SUBSTRING(v_conditions_list, v_pos + 1);
                
                IF v_current_id != '' THEN
    
                    IF NOT EXISTS (SELECT 1 FROM clinical_conditions WHERE id = CAST(v_current_id AS UNSIGNED)) THEN
                        SET v_error_message = CONCAT('La condición clínica con ID ', v_current_id, ' no existe');
                        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_error_message;
                    END IF;
                    
                    INSERT INTO clinical_history_and_conditions (id_c_condition, id_c_history)
                    VALUES (CAST(v_current_id AS UNSIGNED), v_clinical_history_id);
                END IF;
            END IF;
        END WHILE;
    END IF;
    
    -- 5. INSERTAR VACUNAS
    IF p_vaccines_ids IS NOT NULL AND p_vaccines_ids != '' THEN
        SET v_vaccines_list = CONCAT(p_vaccines_ids, ',');
        SET v_pos = 1;
        
        WHILE v_pos > 0 DO
            SET v_pos = LOCATE(',', v_vaccines_list);
            IF v_pos > 0 THEN
                SET v_current_id = LEFT(v_vaccines_list, v_pos - 1);
                SET v_vaccines_list = SUBSTRING(v_vaccines_list, v_pos + 1);
                
                IF v_current_id != '' THEN
                    -- Validar que la vacuna existe
                    IF NOT EXISTS (SELECT 1 FROM vaccines WHERE id = CAST(v_current_id AS UNSIGNED)) THEN
                        SET v_error_message = CONCAT('La vacuna con ID ', v_current_id, ' no existe');
                        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_error_message;
                    END IF;
                    
                    INSERT INTO vaccines_and_clinical_history (id_vaccine, id_c_history)
                    VALUES (CAST(v_current_id AS UNSIGNED), v_clinical_history_id);
                END IF;
            END IF;
        END WHILE;
    END IF;
    
    IF p_medications_json IS NOT NULL AND p_medications_json != '' AND p_medications_json != '[]' THEN
        SET v_medications_count = JSON_LENGTH(p_medications_json);
        
        IF v_medications_count > 0 THEN
            SET v_counter = 0;
            WHILE v_counter < v_medications_count DO
                SET @medication_name = JSON_UNQUOTE(JSON_EXTRACT(p_medications_json, CONCAT('$[', v_counter, '].medication')));
                SET @medication_dosage = JSON_UNQUOTE(JSON_EXTRACT(p_medications_json, CONCAT('$[', v_counter, '].dosage')));
                SET @medication_type = JSON_UNQUOTE(JSON_EXTRACT(p_medications_json, CONCAT('$[', v_counter, '].type')));
                
                INSERT INTO clinical_medication (m_medication, m_dosage, m_treatment_type, id_clinical_history)
                VALUES (@medication_name, @medication_dosage, @medication_type, v_clinical_history_id);
                
                SET v_counter = v_counter + 1;
            END WHILE;
        END IF;
    END IF;
    
    IF p_subprograms_ids IS NOT NULL AND p_subprograms_ids != '' THEN
        SET v_subprograms_list = CONCAT(p_subprograms_ids, ',');
        SET v_pos = 1;
        
        WHILE v_pos > 0 DO
            SET v_pos = LOCATE(',', v_subprograms_list);
            IF v_pos > 0 THEN
                SET v_current_id = LEFT(v_subprograms_list, v_pos - 1);
                SET v_subprograms_list = SUBSTRING(v_subprograms_list, v_pos + 1);
                
                IF v_current_id != '' THEN
    
                    IF NOT EXISTS (
                        SELECT 1 FROM sub_programs 
                        WHERE id = CAST(v_current_id AS UNSIGNED) AND id_program = p_program_id
                    ) THEN
                        SET v_error_message = CONCAT('El subprograma con ID ', v_current_id, ' no existe o no pertenece al programa ', p_program_id);
                        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_error_message;
                    END IF;
                    
                    INSERT INTO older_adult_subprogram (id_older_adult, id_sub_program)
                    VALUES (v_older_adult_id, CAST(v_current_id AS UNSIGNED));
                END IF;
            END IF;
        END WHILE;
    END IF;
    
    COMMIT;
    
    SELECT 
        v_older_adult_id as older_adult_id,
        v_family_id as family_id,
        v_clinical_history_id as clinical_history_id,
        'SUCCESS' as status,
        'Expediente virtual creado exitosamente' as message;
END$$
DELIMITER ;

-- SP para eliminar la ficha virtual de un adulto mayor mediante identificación (cédula)
DELIMITER $$
CREATE PROCEDURE DeleteVirtualFile(
    IN p_older_adult_identification VARCHAR(20)
)
BEGIN
    DECLARE v_older_adult_id INT DEFAULT NULL;
    DECLARE v_family_id INT DEFAULT NULL;
    DECLARE v_clinical_history_id INT DEFAULT NULL;
    DECLARE v_error_message VARCHAR(500);
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1
            v_error_message = MESSAGE_TEXT;
        SELECT CONCAT('Error: ', v_error_message) as error_message;
    END;
    
    START TRANSACTION;
    
    SELECT id, id_family INTO v_older_adult_id, v_family_id
    FROM older_adult 
    WHERE oa_identification = p_older_adult_identification;
    
    IF v_older_adult_id IS NULL THEN
        SET v_error_message = CONCAT('No existe un adulto mayor con identificación: ', p_older_adult_identification);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_error_message;
    END IF;
    
    SELECT MAX(id) INTO v_clinical_history_id FROM clinical_history 
    WHERE create_at >= (SELECT create_at FROM older_adult WHERE id = v_older_adult_id);
    
    DELETE FROM older_adult_subprogram WHERE id_older_adult = v_older_adult_id;
    
    DELETE FROM emergency_contacts WHERE id_older_adult = v_older_adult_id;
    
    IF v_clinical_history_id IS NOT NULL THEN
        DELETE FROM clinical_medication WHERE id_clinical_history = v_clinical_history_id;
        
        DELETE FROM clinical_history_and_conditions WHERE id_c_history = v_clinical_history_id;
        
        DELETE FROM vaccines_and_clinical_history WHERE id_c_history = v_clinical_history_id;
        
        DELETE FROM clinical_history WHERE id = v_clinical_history_id;
    END IF;
    
    DELETE FROM older_adult WHERE id = v_older_adult_id;
    
    IF v_family_id IS NOT NULL THEN
        DELETE FROM older_adult_family WHERE id = v_family_id;
    END IF;
    
    COMMIT;
    
    SELECT 
        v_older_adult_id as deleted_older_adult_id,
        p_older_adult_identification as identification,
        'SUCCESS' as status,
        'Expediente virtual eliminado exitosamente' as message;
END$$
DELIMITER ;

-- SP para obtener la ficha virtual de un adulto mayor a través de identificaicón (cédula)
DELIMITER $$
CREATE PROCEDURE GetVirtualFile(
    IN p_older_adult_identification VARCHAR(20)
)
BEGIN
    DECLARE v_older_adult_id INT DEFAULT NULL;
    DECLARE v_error_message VARCHAR(500);
    -- Validar que el adulto mayor existe
    SELECT id INTO v_older_adult_id
    FROM older_adult 
    WHERE oa_identification = p_older_adult_identification;
    
    IF v_older_adult_id IS NULL THEN
        SELECT CONCAT('No existe un adulto mayor con identificación: ', p_older_adult_identification) as error_message;
    ELSE
        -- Retornar información completa del expediente virtual
        SELECT 
            oa.*,
            p.p_name as program_name,
            fam.*,
            GROUP_CONCAT(DISTINCT sp.sp_name) as subprograms
        FROM older_adult oa
        LEFT JOIN programs p ON oa.id_program = p.id
        LEFT JOIN older_adult_family fam ON oa.id_family = fam.id
        LEFT JOIN older_adult_subprogram oas ON oa.id = oas.id_older_adult
        LEFT JOIN sub_programs sp ON oas.id_sub_program = sp.id
        WHERE oa.id = v_older_adult_id
        GROUP BY oa.id;
    END IF;

END$$
DELIMITER ;





SELECT * FROM users;
SELECT * FROM user_two_factor;
SELECT * FROM entrances_exits;
SELECT * FROM older_adult;
SELECT * FROM older_adult_family;
SELECT * FROM older_adult_subprogram;
SELECT * FROM clinical_conditions;
SELECT * FROM vaccines;
SELECT * FROM clinical_history;
SELECT * FROM clinical_history_and_conditions;
SELECT * FROM vaccines_and_clinical_history;
SELECT * FROM clinical_medication;
SELECT * FROM programs;
SELECT * FROM sub_programs;




