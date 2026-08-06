-- =============================================================================
-- 013_system_user.sql
-- Creates a reserved system user for automated/audit actions (e.g., anonymous user requests).
-- ID 999999 is reserved to avoid collision with real users (auto-increment starts at 1).
-- =============================================================================

-- Insert system user if not exists
INSERT INTO users (
    id,
    u_identification,
    u_name,
    u_f_last_name,
    u_s_last_name,
    u_email,
    u_email_verified,
    u_password,
    u_is_active,
    create_at
)
VALUES (
    999999,
    'SYSTEM',
    'Sistema',
    'Automatizado',
    NULL,
    'system@hogarancianos.local',
    TRUE,
    '', -- no password, cannot login
    FALSE, -- inactive: never appears in active user lists, cannot login
    NOW()
)
ON CONFLICT (id) DO NOTHING;

-- Ensure the user has no roles (cannot login, no permissions)

COMMENT ON TABLE users IS '999999 = system user for audit/anonymous actions; do not delete or assign roles';

-- End of 013.