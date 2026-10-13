-- =============================================================================
-- 000_seed_roles.sql (optional, run after all numbered migrations)
-- Seeds the default roles for the Sistema Integral de Gestión Holística y de Asistencia (SIGHA) platform.
-- Safe to re-run: uses ON CONFLICT DO NOTHING.
-- =============================================================================

-- roles table is auto-populated by the e_user_role ENUM, but we still insert
-- explicit rows so each role has a stable numeric ID for FK references.
INSERT INTO roles (id, r_name) VALUES
  (1, 'super admin'),
  (2, 'admin'),
  (3, 'director'),
  (4, 'nurse'),
  (5, 'physiotherapist'),
  (6, 'psychologist'),
  (7, 'social worker'),
  (8, 'not specified')
ON CONFLICT (id) DO NOTHING;

-- Make sure the sequence picks up after the highest seeded id.
SELECT setval(
  pg_get_serial_sequence('roles', 'id'),
  GREATEST((SELECT MAX(id) FROM roles), 1)
);
