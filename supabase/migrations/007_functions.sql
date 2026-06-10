-- =============================================================================
-- 007_functions.sql
-- PL/pgSQL functions and utility procedures that replace the MySQL stored
-- procedures of the legacy schema.
-- Run after 006.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- clean_expired_sessions()
-- Marks expired user_sessions as inactive and purges old inactive ones.
-- Schedule via Supabase pg_cron or run manually.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clean_expired_sessions(retention_days INTEGER DEFAULT 30)
RETURNS TABLE (marked_inactive INTEGER, purged INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
  v_marked INTEGER;
  v_purged  INTEGER;
BEGIN
  UPDATE user_sessions
     SET is_active = FALSE
   WHERE expires_at < NOW() AND is_active = TRUE;
  GET DIAGNOSTICS v_marked = ROW_COUNT;

  DELETE FROM user_sessions
   WHERE is_active = FALSE
     AND last_activity < (NOW() - (retention_days || ' days')::INTERVAL);
  GET DIAGNOSTICS v_purged = ROW_COUNT;

  RETURN QUERY SELECT v_marked, v_purged;
END;
$$;

-- -----------------------------------------------------------------------------
-- clean_expired_tokens()
-- Removes expired, unused password reset and email verification tokens.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clean_expired_tokens()
RETURNS TABLE (pwreset_deleted INTEGER, evtoken_deleted INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
  v_pw INTEGER;
  v_ev INTEGER;
BEGIN
  DELETE FROM password_reset_tokens WHERE expires_at < NOW() AND used = FALSE;
  GET DIAGNOSTICS v_pw = ROW_COUNT;

  DELETE FROM email_verification_tokens WHERE expires_at < NOW() AND verified = FALSE;
  GET DIAGNOSTICS v_ev = ROW_COUNT;

  RETURN QUERY SELECT v_pw, v_ev;
END;
$$;

-- -----------------------------------------------------------------------------
-- get_failed_login_stats(time_window_hours)
-- Returns rows of (email, ip, failed_attempts, last_attempt, reason) where
-- the count of failed attempts in the given window is >= 3.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_failed_login_stats(time_window_hours INTEGER)
RETURNS TABLE (
  email           VARCHAR(256),
  ip_address      VARCHAR(45),
  failed_attempts BIGINT,
  last_attempt    TIMESTAMPTZ,
  failure_reason  VARCHAR(100)
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    la.email,
    la.ip_address,
    COUNT(*)::BIGINT                 AS failed_attempts,
    MAX(la.attempted_at)            AS last_attempt,
    la.failure_reason
  FROM login_attempts la
  WHERE la.attempt_successful = FALSE
    AND la.attempted_at > (NOW() - (time_window_hours || ' hours')::INTERVAL)
  GROUP BY la.email, la.ip_address, la.failure_reason
  HAVING COUNT(*) >= 3
  ORDER BY failed_attempts DESC, last_attempt DESC;
END;
$$;

-- -----------------------------------------------------------------------------
-- log_audit()
-- Convenience function to write a digital record + an audit report row in a
-- single call. Mirrors the legacy `sp_log_audit` MySQL procedure.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION log_audit(
  p_user_id        INTEGER,
  p_dr_action      e_dr_action,
  p_dr_table_name  VARCHAR(100),
  p_dr_record_id   INTEGER,
  p_dr_description TEXT,
  p_ar_type        e_audit_type      DEFAULT 'other',
  p_ar_action      e_audit_action    DEFAULT 'other',
  p_ar_entity_name VARCHAR(100)      DEFAULT NULL,
  p_ar_entity_id   INTEGER           DEFAULT NULL,
  p_ar_observations TEXT             DEFAULT NULL,
  p_ar_ip_address  VARCHAR(45)       DEFAULT NULL,
  p_ar_user_agent  TEXT              DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_id INTEGER;
BEGIN
  -- digital record
  INSERT INTO digital_record (dr_user_id, dr_action, dr_table_name, dr_record_id, dr_description)
  VALUES (p_user_id, p_dr_action, p_dr_table_name, p_dr_record_id, p_dr_description)
  RETURNING id INTO v_id;

  -- audit report
  INSERT INTO audit_reports (
    ar_type, ar_entity_name, ar_entity_id, ar_action, ar_observations,
    ar_start_date, ar_ip_address, ar_user_agent, id_generator
  )
  VALUES (
    p_ar_type, p_ar_entity_name, p_ar_entity_id, p_ar_action, p_ar_observations,
    NOW(), p_ar_ip_address, p_ar_user_agent, p_user_id
  );

  RETURN v_id;
END;
$$;

-- -----------------------------------------------------------------------------
-- update_at triggers: mirror MySQL's "ON UPDATE CURRENT_TIMESTAMP" behavior
-- for tables that have an `updated_at` column. This is a generic helper.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_two_factor_updated_at ON user_two_factor;
CREATE TRIGGER trg_user_two_factor_updated_at
BEFORE UPDATE ON user_two_factor
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -----------------------------------------------------------------------------
-- TODO: port of `CreateVirtualFile(...)` procedure.
-- The original MySQL procedure is ~300 lines of validation, transaction
-- handling, and split logic for family / clinical history / medications.
-- The recommended long-term path is to move this business logic into the
-- backend's `VirtualRecordsService` (NestJS) — the database should stay
-- thin. A direct port to PL/pgSQL is left as a follow-up.
-- -----------------------------------------------------------------------------

-- End of 007.
