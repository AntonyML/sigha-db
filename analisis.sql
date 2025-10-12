DROP DATABASE IF EXISTS hogar_de_ancianos;
CREATE DATABASE hogar_de_ancianos;
USE hogar_de_ancianos;

-- ####################################################################################

-- Tabla de roles
CREATE TABLE roles (
    id INT AUTO_INCREMENT PRIMARY KEY,
    r_name ENUM('super admin', 'admin', 'director', 'nurse', 'physiotherapist', 'psychologist', 'social worker', 'not specified') DEFAULT 'not specified'
);

-- Tabla de permisos
CREATE TABLE permissions (
	id INT AUTO_INCREMENT PRIMARY KEY,
    p_name VARCHAR(50) NOT NULL,
    id_role INT,
    FOREIGN KEY (id_role) REFERENCES roles(id)
);

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
    u_token VARCHAR(255) NULL,
    create_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    role_id INT,
    FOREIGN KEY (role_id) REFERENCES roles(id)
);

-- ####################################################################################

-- Tabla para guardar los cambios de roles en usuarios
CREATE TABLE role_changes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,          -- Usuario afectado
    old_role VARCHAR(50),
    new_role VARCHAR(50),
    changed_by INT NOT NULL,       -- Admin que hizo el cambio
    changed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id),
    FOREIGN KEY (changed_by) REFERENCES users(id)
);

-- ####################################################################################

-- Tabla para programas del hogar
CREATE TABLE programs (
	id INT AUTO_INCREMENT PRIMARY KEY,
    p_name VARCHAR(300) NOT NULL,
    p_description TEXT NOT NULL,
	p_type ENUM('health', 'recreation', 'education', 'community', 'research', 'other') NOT NULL DEFAULT 'other',
	p_observations TEXT NULL, 					-- Notas o comentarios
    p_start_date DATE NOT NULL,
    p_end_date DATE NULL,
	p_budget DECIMAL(12,2) NULL,				-- Presupuesto destinado al programa
    p_status ENUM('planned', 'in progress', 'completed', 'cancelled') NOT NULL DEFAULT 'planned',
    create_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Tabla para agregar participantes a un programa
CREATE TABLE program_participants (
    id INT AUTO_INCREMENT PRIMARY KEY,
    pp_identification VARCHAR(20) NOT NULL,
    pp_name VARCHAR(50) NOT NULL,
    pp_f_last_name VARCHAR(50) NULL,
    pp_s_last_name VARCHAR(50) NULL,
    pp_role ENUM('employee', 'volunteer', 'external person', 'older_adult', 'not specified') DEFAULT 'not specified',
    id_program INT,
    FOREIGN KEY (id_program) REFERENCES programs(id)
);

-- ####################################################################################

-- Tabla para familiares de un paciente
CREATE TABLE older_adult_family (
	id INT AUTO_INCREMENT PRIMARY KEY,
	pf_identification VARCHAR(20) NOT NULL,
    pf_name VARCHAR(50) NOT NULL,
    pf_f_last_name VARCHAR(50) NOT NULL,
    pf_s_last_name VARCHAR(50) NOT NULL,
    pf_phone_number VARCHAR(20) NULL,
    pf_email VARCHAR(256) UNIQUE NOT NULL,
    pf_kinship  ENUM(
		'son', 'daughter', 'grandson', 'granddaughter', 'brother', 'sister',
        'nephew', 'niece', 'husband', 'wife', 'legal guardian', 'other', 'not specified'
	) NOT NULL DEFAULT 'not specified',
    create_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Tabla de adultos mayores
CREATE TABLE older_adult (
    id INT AUTO_INCREMENT PRIMARY KEY,
    oa_identification VARCHAR(20) NOT NULL UNIQUE,
    oa_name VARCHAR(50) NOT NULL,
    oa_f_last_name VARCHAR(50) NOT NULL,
    oa_s_last_name VARCHAR(50) NULL,
    oa_birthdate DATE,
    oa_marital_status ENUM('single', 'married', 'divorced', 'widowed', 'common law union', 'separated', 'not specified') DEFAULT 'not specified',
    oa_dwelling TEXT NOT NULL,
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
    oa_area_of_origin VARCHAR(300) NOT NULL,
	oa_children_count TINYINT UNSIGNED DEFAULT 0,
    oa_status ENUM('alive', 'dead') DEFAULT 'alive',
    oa_death_date DATE NULL, 					  		-- En caso de que haya muerto, guardar fecha
    oa_economic_income DECIMAL(10, 2) NOT NULL,	  		-- Ingreso económico del hogar (colones)
    oa_phone_numner VARCHAR(20) NOT NULL,
    oa_email VARCHAR(256) NOT NULL,
    oa_profile_photo_url VARCHAR(255) NULL,
    -- adicionales
	oa_gender ENUM('male', 'female', 'not specified') DEFAULT 'not specified',
	oa_blood_type ENUM('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'UNKNOWN') DEFAULT 'UNKNOWN',
	create_at DATETIME DEFAULT CURRENT_TIMESTAMP,
	-- llaves foráneas
    id_program INT,
    id_family INT,
    FOREIGN KEY (id_program) REFERENCES programs(id),
    FOREIGN KEY (id_family) REFERENCES older_adult_family(id)
);

-- Tabla de números de emergencia para adulto mayor cuando es paciente
CREATE TABLE emergency_contacts (
	id INT AUTO_INCREMENT PRIMARY KEY,
    en_phone_number VARCHAR(20) NOT NULL,
	create_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    id_older_adult INT,
    FOREIGN KEY (id_older_adult) REFERENCES older_adult(id)
);

-- ####################################################################################

-- Tabla para guardar los cambios en datos de adultos mayores
CREATE TABLE older_adult_updates (
    id INT AUTO_INCREMENT PRIMARY KEY,
    id_older_adult INT NOT NULL,
    field_changed VARCHAR(100) NOT NULL,
    old_value TEXT NULL,
    new_value TEXT NULL,
    changed_by INT NOT NULL,
    changed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_older_adult) REFERENCES older_adult(id),
    FOREIGN KEY (changed_by) REFERENCES users(id)
);

-- ####################################################################################

-- Tabla de padecimeintos
CREATE TABLE clinical_conditions (
	id INT AUTO_INCREMENT PRIMARY KEY,
	cc_name VARCHAR(55) NOT NULL
);

-- Tabla de tipos de vacunas
CREATE TABLE vaccines (
	id INT AUTO_INCREMENT PRIMARY KEY,
    v_name VARCHAR(80) NOT NULL
);

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
	create_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Tabla relación de clinical_conditions y clinical_history
CREATE TABLE clinical_history_and_conditions (
	id_c_condition INT,
    id_c_history INT,
    FOREIGN KEY (id_c_condition) REFERENCES clinical_conditions(id),
    FOREIGN KEY (id_c_history) REFERENCES clinical_history(id)
);

-- Tabla relación de vaccines y clinical_history
CREATE TABLE vaccines_and_clinical_history (
	id_vaccine INT,
    id_c_history INT,
    FOREIGN key (id_vaccine) REFERENCES vaccines(id),
	FOREIGN key (id_c_history) REFERENCES clinical_history(id)
);

-- Tabla de medicación
CREATE TABLE clinical_medication (
	id INT AUTO_INCREMENT PRIMARY KEY,
    m_medication VARCHAR(500) NOT NULL,
    m_dosage VARCHAR(30) NOT NULL,
    m_treatment_type ENUM('temporary', 'chronic', 'preventive', 'other') NOT NULL DEFAULT 'other',
    id_clinical_history INT,
    FOREIGN KEY (id_clinical_history) REFERENCES clinical_history(id)
);

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
    FOREIGN KEY (id_manager) REFERENCES users(id)
);

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
    FOREIGN KEY (id_area) REFERENCES specialized_area(id),
    FOREIGN KEY (id_patient) REFERENCES older_adult(id),
    FOREIGN KEY (id_staff) REFERENCES users(id)
);

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
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    id_appointment INT,
    FOREIGN KEY (id_appointment) REFERENCES specialized_appointment(id)
);

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
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    id_appointment INT,
    FOREIGN KEY (id_appointment) REFERENCES specialized_appointment(id)
);

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
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    id_appointment INT,
    FOREIGN KEY (id_appointment) REFERENCES specialized_appointment(id)
);

-- Tabla para guardar datos de trabajo socia
CREATE TABLE social_work_reports (
    id INT AUTO_INCREMENT PRIMARY KEY,
    sw_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    sw_visit_type ENUM('home visit', 'institutional visit', 'interview', 'follow_up') DEFAULT 'interview',
    sw_family_relationship TEXT NULL,
    sw_economic_assessment TEXT NULL,
    sw_social_support TEXT NULL,
    sw_observations TEXT,
    sw_recommendations TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    id_appointment INT,
    FOREIGN KEY (id_appointment) REFERENCES specialized_appointment(id)
);

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
    FOREIGN KEY (id_older_adult) REFERENCES older_adult(id),
    FOREIGN KEY (id_appointment) REFERENCES specialized_appointment(id),
    FOREIGN KEY (id_staff) REFERENCES users(id)
);

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
    FOREIGN KEY (dr_user_id) REFERENCES users(id)
);

-- Tabla de auditoría (conteo de auditorías generadas)
CREATE TABLE audit_reports (
    id INT AUTO_INCREMENT PRIMARY KEY,
    ar_audit_number INT UNIQUE,
    ar_type ENUM('general_actions', 'role_changes', 'older_adult_updates', 'system_access', 'other') DEFAULT 'other',
    ar_start_date DATETIME NOT NULL,
    ar_end_date DATETIME NOT NULL,
	create_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    id_generator INT,
    FOREIGN KEY (id_generator) REFERENCES users(id)
);

-- ######################################################################################################################################################

DELIMITER //
CREATE PROCEDURE generate_audit_report (
    IN audit_type ENUM('general_actions', 'role_changes', 'older_adult_updates', 'system_access'),
    IN start_date DATETIME,
    IN end_date DATETIME,
    IN admin_id INT
)
BEGIN
    DECLARE next_audit_number INT;

    -- Obtener número consecutivo de auditoría
    SELECT IFNULL(MAX(ar_audit_number), 0) + 1 INTO next_audit_number FROM audit_reports;

    -- Insertar registro en audit_reports
    INSERT INTO audit_reports (
        ar_audit_number, ar_type, ar_start_date, ar_end_date, id_generator
    ) VALUES (
        next_audit_number, audit_type, start_date, end_date, admin_id
    );

    -- Devolver datos según tipo
    CASE audit_type
        WHEN 'general_actions' THEN
            SELECT 
				u.id,
                u.u_name AS user_name,
                dr.dr_action AS action,
                dr.dr_table_name AS table_name,
                dr.dr_record_id AS record_id,
                dr.dr_description AS description,
                dr.dr_timestamp AS timestamp
            FROM digital_record dr
            INNER JOIN users u ON dr.dr_user_id = u.id
            WHERE dr.dr_timestamp BETWEEN start_date AND end_date
            ORDER BY dr.dr_timestamp DESC;

        WHEN 'role_changes' THEN
            SELECT 
                u1.u_name AS admin_who_changed,
                u2.u_name AS user_affected,
                rc.old_role,
                rc.new_role,
                rc.changed_at
            FROM role_changes rc
            INNER JOIN users u1 ON rc.changed_by = u1.id
            INNER JOIN users u2 ON rc.user_id = u2.id
            WHERE rc.changed_at BETWEEN start_date AND end_date
            ORDER BY rc.changed_at DESC;

        WHEN 'older_adult_updates' THEN
            SELECT 
                u.u_name AS user_name,
                oaua.field_changed,
                oaua.old_value,
                oaua.new_value,
                oaua.changed_at
            FROM older_adult_updates oaua
            INNER JOIN users u ON oaua.changed_by = u.id
            WHERE oaua.changed_at BETWEEN start_date AND end_date
            ORDER BY oaua.changed_at DESC;

        WHEN 'system_access' THEN
            SELECT 
                u.u_name AS user_name,
                dr.dr_action AS action,
                dr.dr_timestamp AS timestamp,
                dr.dr_description AS description
            FROM digital_record dr
            INNER JOIN users u ON dr.dr_user_id = u.id
            WHERE dr.dr_action IN ('login', 'logout')
            AND dr.dr_timestamp BETWEEN start_date AND end_date
            ORDER BY dr.dr_timestamp DESC;
    END CASE;
END //
DELIMITER ;












