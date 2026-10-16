# Supabase / Postgres Database (SIGHA)

Arquitectura relacional refactorizada bajo principios de **Diseño Guiado por el Dominio (DDD)**, **Zero-Waste DB** y **PostgreSQL / Supabase Nativo**.

---

## 1. Esquemas Modulares de Dominio

La base de datos se organiza en 6 esquemas lógicos desacoplados:

| Esquema | Propósito | Tablas Principales |
|---|---|---|
| `core` | Identidad universal, relaciones humanas y perfiles dinámicos | `persona`, `documento_identidad`, `medio_contacto`, `direccion`, `relacion_persona`, `persona_rol`, `perfil`, `perfil_digital`, `plantilla_perfil`, `seccion_campo`, `definicion_campo` |
| `operacion` | Logística diaria, camas, estancias, bitácora y accesos | `pabellon`, `habitacion`, `cama`, `estancia`, `bitacora_entrada`, `bitacora_acuse`, `registro_acceso`, `programa`, `inscripcion_programa` |
| `clinico` | Encuentros médicos, signos vitales, escalas, MAR Kardex y vademécum | `encuentro_clinico`, `signo_vital`, `escala_evaluacion`, `condicion_paciente`, `prescripcion_medicamento`, `administracion_kardex`, `vacuna_paciente`, catálogos (`catalogo_cie10`, `catalogo_medicamento`, `catalogo_vacuna`) |
| `seguridad` | Autenticación, multi-tenancy, RBAC granular, 2FA y sesiones | `organizacion`, `usuario`, `miembro_organizacion`, `rol`, `permiso`, `rol_permiso`, `sesion`, `dos_factores`, `intento_login`, `token_recuperacion` |
| `auditoria` | Libro mayor inmutable para trazabilidad de mutaciones | `evento` |
| `analitica` | Vistas materializadas y de reporte consolidado | `v_resumen_residentes` |

---

## 2. Decisiones Arquitectónicas Clave

1. **UUIDv7 Híbrido:**
   - Entidades de negocio (`persona`, `perfil`, `estancia`, etc.): `UUIDv7` ordenable temporalmente mediante la función nativa `public.uuidv7()`.
   - Multi-tenant (`tenant_id` / `organizacion.id`) y usuario (`usuario.id`): `INTEGER` para preservar intactos los contratos de sesión (`app.current_tenant_id`, `app.current_user_id`).
   - Bitácora y eventos de alto volumen (`bitacora_entrada`, `auditoria.evento`): `BIGINT GENERATED ALWAYS AS IDENTITY`.
2. **Motor de Perfil Digital Dinámico:**
   - La estructura de expediente se configura desde la UI mediante `plantilla_perfil` → `seccion_campo` → `definicion_campo`.
   - Los datos se almacenan en `perfil_digital.datos` (`JSONB`) indexados con `GIN (datos jsonb_path_ops)`.
   - El trigger `core.trg_validar_perfil_digital` garantiza la integridad de los campos obligatorios en el motor.
3. **Camas y Estancias sin Solapamiento:**
   - Constraint `EXCLUDE USING gist (cama_id WITH =, rango_estancia WITH &&)` en `operacion.estancia` que previene matemáticamente cualquier doble ocupación de cama.
   - Sincronización automática de estado (`ocupada`/`disponible`) y de `core.perfil.cama_actual_id` mediante trigger.
4. **Bitácora Operativa (sustituye a "Memo"):**
   - Hilos de conversación (`padre_id`), categorías, urgencias, visibilidad y confirmación de lectura (`bitacora_acuse`).
5. **Aislamiento Multi-Tenant:**
   - RLS habilitado y forzado en todas las tablas con `tenant_id` para el rol `sigha_app`.

---

## 3. Ejecución y Pruebas

Para aplicar el baseline o correr la suite de verificación automatizada:

```bash
# Aplicar migración 001_baseline.sql en desarrollo
bun run apply:baseline

# Ejecutar suite de pruebas de esquema, restricciones e integridad E2E
bun run test:baseline
```
