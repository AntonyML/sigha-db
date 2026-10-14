# Registro de cambios

Registra aquí solo cambios integrados en `dev`. El agente que integra agrega una entrada bajo el lock `dev-sigha-db` tras re-verificar el cambio en `dev`; las demás tareas no editan este archivo.

Formato: `YYYY-MM-DD | <taskId> | tipo: resumen | verificación: resultado`.
2026-10-13 | sigha-db-20261013-9moj | feat: crear organizations y organization_members; migrar usuarios a ASOPOGUA | verificación: Supabase dev 50/50 memberships primarias, 0 huérfanos; re-aplicación idempotente OK
2026-10-13 | sigha-db-20261013-s62v | refactor: renombrar a identidad SIGHA (AGENTS, seed, comentario 004) + migración 014 email system user | verificación: 014 aplicada en Supabase dev (fila 999999=system@sigha.local, LEGACY_COUNT=0); 013 intacta; re-verificado en dev
2026-10-14 | sigha-db-20261014-pswj | feat: migración 019 alinea create_virtual_file con DTO (familia completa obligatoria, document types persistidos, condicionales oa_other/fallecido/neoplasias) | verificación: pglast parse OK (DROP-48 + CREATE 50 params con defaults); paridad servicio-50-args vs firma OK; orden 018→019 OK; diff --check OK; PENDIENTE aplicar 019 en Supabase dev (sin acceso en esta sesión) antes de desplegar API-50-args
2026-10-14 | sigha-db-20261014-pswj | nota: migración 019 APLICADA en Supabase dev (vía infisical dev) | verificación: huella dev OK (50 usuarios + ASOPOGUA); pre 1×48 args; apply transaccional OK; post 1×50 args con 2 defaults; 5 pruebas negativas OK con mensajes nuevos sin escribir filas; deploy API-50-args habilitado
