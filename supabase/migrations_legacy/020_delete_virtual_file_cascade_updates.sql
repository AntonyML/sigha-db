-- =============================================================================
-- 020_delete_virtual_file_cascade_updates.sql
-- Habilita la eliminación en cascada para older_adult_updates y actualiza la
-- función delete_virtual_file():
--   * Cambia fk_oau_adult a ON DELETE CASCADE para que cualquier registro de
--     auditoría de actualizaciones (older_adult_updates) asociado al adulto
--     mayor no bloquee su eliminación.
--   * Actualiza delete_virtual_file() para limpiar explícitamente
--     older_adult_updates y proteger la eliminación de older_adult_family si
--     otro adulto mayor la comparte.
-- Idempotente y re-ejecutable.
-- Run after 019.
-- =============================================================================

-- 1. Actualizar la clave foránea en older_adult_updates a ON DELETE CASCADE
ALTER TABLE older_adult_updates
  DROP CONSTRAINT IF EXISTS fk_oau_adult;

ALTER TABLE older_adult_updates
  ADD CONSTRAINT fk_oau_adult
  FOREIGN KEY (id_older_adult)
  REFERENCES older_adult (id)
  ON DELETE CASCADE;

-- 2. Actualizar función delete_virtual_file()
CREATE OR REPLACE FUNCTION delete_virtual_file(p_older_adult_identification VARCHAR(20))
RETURNS TABLE (
  deleted_older_adult_id INTEGER,
  identification         VARCHAR(20),
  status                 TEXT,
  message                TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_older_adult_id      INTEGER;
  v_family_id           INTEGER;
  v_clinical_history_id INTEGER;
BEGIN
  SELECT id, id_family
    INTO v_older_adult_id, v_family_id
    FROM older_adult
   WHERE oa_identification = p_older_adult_identification;

  IF v_older_adult_id IS NULL THEN
    RAISE EXCEPTION 'No existe un adulto mayor con identificación: %', p_older_adult_identification;
  END IF;

  -- Resolve the most recent clinical history for THIS older adult.
  -- The legacy MySQL implementation filtered on create_at, which could
  -- accidentally match a clinical_history row that belongs to a different
  -- older adult (e.g. two patients created in the same second). We filter
  -- on id_older_adult instead so we can never touch another patient's data.
  -- The FOR UPDATE lock on the subquery prevents two concurrent deletes
  -- from picking the same row.
  SELECT MAX(id)
    INTO v_clinical_history_id
    FROM (
      SELECT id
        FROM clinical_history
       WHERE id_older_adult = v_older_adult_id
       ORDER BY id DESC
       LIMIT 1
       FOR UPDATE
    ) AS ch;

  -- Delete ALL clinical_history rows that belong to this older adult.
  -- The M:N relations (clinical_history_and_conditions, vaccines_and_clinical_history)
  -- and clinical_medication rows are removed by their ON DELETE CASCADE
  -- constraints.
  DELETE FROM clinical_history WHERE id_older_adult = v_older_adult_id;

  -- Direct deletes (the M:N relations and clinical_medication rows are
  -- removed by ON DELETE CASCADE).
  -- older_adult_updates se elimina explícitamente para consistencia y defensa
  -- en profundidad, respaldado por la restricción fk_oau_adult ON DELETE CASCADE.
  DELETE FROM older_adult_updates    WHERE id_older_adult = v_older_adult_id;
  DELETE FROM older_adult_subprogram WHERE id_older_adult = v_older_adult_id;
  DELETE FROM emergency_contacts     WHERE id_older_adult = v_older_adult_id;

  DELETE FROM older_adult WHERE id = v_older_adult_id;

  -- Solo eliminar el registro familiar si ningún otro adulto mayor lo comparte
  IF v_family_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM older_adult WHERE id_family = v_family_id
  ) THEN
    DELETE FROM older_adult_family WHERE id = v_family_id;
  END IF;

  RETURN QUERY SELECT
    v_older_adult_id,
    p_older_adult_identification,
    'SUCCESS'::TEXT,
    'Expediente virtual eliminado exitosamente'::TEXT;
END;
$$;

-- End of 020.
