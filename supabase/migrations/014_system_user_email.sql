-- =============================================================================
-- 014_system_user_email.sql
-- Updates the reserved system user's email to the SIGHA identity.
-- Idempotent: scoped UPDATE by reserved id; safe to re-run.
-- Run after 013. Does not touch roles/permissions (system user has none).
-- =============================================================================

UPDATE users
SET u_email = 'system@sigha.local'
WHERE id = 999999 AND u_email IS DISTINCT FROM 'system@sigha.local';

-- End of 014.
