-- =============================================================================
-- 020_revert_delete_virtual_file_cascade_updates.sql
-- Revierte la migración 020:
--   * Restaura fk_oau_adult sin ON DELETE CASCADE.
--   * Restaura delete_virtual_file() a la versión original de 011.
-- =============================================================================

ALTER TABLE older_adult_updates
  DROP CONSTRAINT IF EXISTS fk_oau_adult;

ALTER TABLE older_adult_updates
  ADD CONSTRAINT fk_oau_adult
  FOREIGN KEY (id_older_adult)
  REFERENCES older_adult (id);

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

  DELETE FROM clinical_history WHERE id_older_adult = v_older_adult_id;

  DELETE FROM older_adult_subprogram WHERE id_older_adult = v_older_adult_id;
  DELETE FROM emergency_contacts     WHERE id_older_adult = v_older_adult_id;

  DELETE FROM older_adult WHERE id = v_older_adult_id;

  IF v_family_id IS NOT NULL THEN
    DELETE FROM older_adult_family WHERE id = v_family_id;
  END IF;

  RETURN QUERY SELECT
    v_older_adult_id,
    p_older_adult_identification,
    'SUCCESS'::TEXT,
    'Expediente virtual eliminado exitosamente'::TEXT;
END;
$$;
