DELIMITER $$

CREATE PROCEDURE sp_log_audit(
    IN p_user_id INT,
    IN p_type ENUM('login_attempts','role_changes','older_adult_updates','system_access','clinical_record_changes'),
    IN p_entity_name VARCHAR(100),
    IN p_entity_id INT,
    IN p_action VARCHAR(50),
    IN p_old_value TEXT,
    IN p_new_value TEXT,
    IN p_ip VARCHAR(45),
    IN p_user_agent TEXT,
    IN p_observations TEXT
)
BEGIN
    INSERT INTO audit_reports (
        ar_type,
        ar_entity_name,
        ar_entity_id,
        ar_action,
        ar_old_value,
        ar_new_value,
        ar_start_date,
        ar_end_date,
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
        CASE WHEN p_type = 'login_attempts' AND p_action = 'logout' THEN NOW() ELSE NULL END,
        p_ip,
        p_user_agent,
        p_observations,
        p_user_id
    );
END$$

DELIMITER ;
