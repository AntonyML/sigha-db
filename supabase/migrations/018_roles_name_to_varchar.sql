-- =============================================================================
-- 018_roles_name_to_varchar.sql
-- Habilita la creación de roles con nombres personalizados.
--
-- Convierte roles.r_name de ENUM (e_user_role, limitado a los 8 roles del
-- sistema) a VARCHAR(100), consistente con el maxLength={100} del formulario
-- (CreateRolePage). La aplicación permite crear roles con nombres libres
-- (RoleService solo valida duplicados), pero el ENUM lo impedía: guardar un
-- nombre fuera del enum lanzaba un 500 ("invalid input value for enum
-- e_user_role").
--
-- También se amplían role_changes.rc_old_role / rc_new_role a VARCHAR(100)
-- porque registran nombres de rol y fallarían (value too long) si se guarda
-- un rol personalizado de más de 50 caracteres.
--
-- Los 8 roles del sistema siguen funcionando igual (strings válidos).
-- Idempotente: volver a ejecutar los ALTER con el mismo tipo es un no-op.
-- Run after 017.
-- =============================================================================

ALTER TABLE roles
  ALTER COLUMN r_name TYPE VARCHAR(100);

ALTER TABLE role_changes
  ALTER COLUMN rc_old_role TYPE VARCHAR(100),
  ALTER COLUMN rc_new_role TYPE VARCHAR(100);
