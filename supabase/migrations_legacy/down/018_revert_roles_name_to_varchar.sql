-- =============================================================================
-- 018_revert_roles_name_to_varchar.sql
-- Revierte la migración 018: roles.r_name vuelve a ser ENUM e_user_role y las
-- columnas de role_changes vuelven a VARCHAR(50).
--
-- NOTA: fallará si existen roles con nombres fuera del ENUM (los 8 del
-- sistema). En ese caso habrá que eliminar o renombrar esos roles primero.
-- =============================================================================

ALTER TABLE roles
  ALTER COLUMN r_name TYPE e_user_role USING r_name::e_user_role;

ALTER TABLE role_changes
  ALTER COLUMN rc_old_role TYPE VARCHAR(50),
  ALTER COLUMN rc_new_role TYPE VARCHAR(50);
