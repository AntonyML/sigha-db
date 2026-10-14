# Registro de cambios

Registra aquí solo cambios integrados en `dev`. El agente que integra agrega una entrada bajo el lock `dev-sigha-db` tras re-verificar el cambio en `dev`; las demás tareas no editan este archivo.

Formato: `YYYY-MM-DD | <taskId> | tipo: resumen | verificación: resultado`.
2026-10-13 | sigha-db-20261013-9moj | feat: crear organizations y organization_members; migrar usuarios a ASOPOGUA | verificación: Supabase dev 50/50 memberships primarias, 0 huérfanos; re-aplicación idempotente OK
2026-10-13 | sigha-db-20261013-s62v | refactor: renombrar a identidad SIGHA (AGENTS, seed, comentario 004) + migración 014 email system user | verificación: 014 aplicada en Supabase dev (fila 999999=system@sigha.local, LEGACY_COUNT=0); 013 intacta; re-verificado en dev
