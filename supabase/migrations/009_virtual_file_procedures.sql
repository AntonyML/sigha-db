-- =============================================================================
-- 009_virtual_file_procedures.sql
-- Port of the legacy MySQL stored procedures that operate on the virtual file
-- (expediente virtual) of an older adult:
--   * CreateVirtualFile(p_oa_identification, ..., p_medications_json)
--   * DeleteVirtualFile(p_older_adult_identification) — see safety note below
--   * GetVirtualFile(p_older_adult_identification)
-- Plus a helper that computes the session duration for the logout branch of
-- the legacy sp_log_audit procedure, so the application can stamp the
-- ar_end_date and ar_duration_seconds of the logout row.
--
-- Safety note on delete_virtual_file: the legacy MySQL implementation had
-- two latent bugs that are corrected here. See the function header for
-- details.
-- Run after 008.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- create_virtual_file(...)
-- Creates, in a single transaction, the family member, the older adult, the
-- initial clinical history, the conditions, vaccines, sub-program enrollments
-- and the medications JSON list associated with the new file.
--
-- Parameters that the legacy MySQL version accepted as comma-separated VARCHAR
-- (clinical_conditions_ids, vaccines_ids, subprograms_ids) are exposed as
-- INTEGER[] for cleanness. The medications JSON is exposed as JSONB with the
-- shape:  [ {"medication": "...", "dosage": "...", "type": "..."}, ... ]
-- where "type" must match the e_medication_treatment_type enum values
-- ('temporary', 'chronic', 'preventive', 'other') or be NULL.
--
-- Returns a single row with the new ids and a status / message.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_virtual_file(
  p_oa_identification      VARCHAR(20),
  p_oa_name                VARCHAR(50),
  p_oa_f_last_name         VARCHAR(50),
  p_oa_s_last_name         VARCHAR(50),
  p_oa_birthdate           DATE,
  p_oa_marital_status      e_oa_marital_status,
  p_oa_dwelling            TEXT,
  p_oa_years_schooling     e_oa_years_schooling,
  p_oa_previous_work       VARCHAR(300),
  p_oa_is_retired          BOOLEAN,
  p_oa_has_pension         BOOLEAN,
  p_oa_other               BOOLEAN,
  p_oa_other_description   VARCHAR(300),
  p_oa_area_of_origin      VARCHAR(300),
  p_oa_children_count      SMALLINT,
  p_oa_status              e_oa_status,
  p_oa_death_date          DATE,
  p_oa_economic_income     NUMERIC(10,2),
  p_oa_phone_numner        VARCHAR(20),
  p_oa_email               VARCHAR(256),
  p_oa_profile_photo_url   VARCHAR(255),
  p_oa_gender              e_oa_gender,
  p_oa_blood_type          e_oa_blood_type,
  p_program_id             INTEGER,

  p_pf_identification      VARCHAR(20),
  p_pf_name                VARCHAR(50),
  p_pf_f_last_name         VARCHAR(50),
  p_pf_s_last_name         VARCHAR(50),
  p_pf_phone_number        VARCHAR(20),
  p_pf_email               VARCHAR(256),
  p_pf_kinship             e_pf_kinship,

  p_ch_frequent_falls      BOOLEAN,
  p_ch_weight              NUMERIC(5,2),
  p_ch_height              NUMERIC(4,2),
  p_ch_imc                 NUMERIC(4,1),
  p_ch_blood_pressure      VARCHAR(7),
  p_ch_neoplasms           BOOLEAN,
  p_ch_neoplasms_description VARCHAR(300),
  p_ch_observations        TEXT,
  p_ch_rcvg                e_clinical_rcvg,
  p_ch_vision_problems     BOOLEAN,
  p_ch_vision_hearing      BOOLEAN,

  p_clinical_conditions_ids INTEGER[],
  p_vaccines_ids           INTEGER[],
  p_subprograms_ids        INTEGER[],

  p_medications_json       JSONB
)
RETURNS TABLE (
  older_adult_id       INTEGER,
  family_id            INTEGER,
  clinical_history_id  INTEGER,
  status               TEXT,
  message              TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_older_adult_id      INTEGER;
  v_family_id           INTEGER;
  v_clinical_history_id INTEGER;
  v_med                 JSONB;
BEGIN
  IF p_oa_identification IS NULL OR btrim(p_oa_identification) = '' THEN
    RAISE EXCEPTION 'La identificación del adulto mayor es requerida';
  END IF;

  IF p_oa_name IS NULL OR btrim(p_oa_name) = '' THEN
    RAISE EXCEPTION 'El nombre del adulto mayor es requerido';
  END IF;

  IF p_oa_f_last_name IS NULL OR btrim(p_oa_f_last_name) = '' THEN
    RAISE EXCEPTION 'El primer apellido del adulto mayor es requerido';
  END IF;

  IF p_oa_previous_work IS NULL OR btrim(p_oa_previous_work) = '' THEN
    RAISE EXCEPTION 'El trabajo previo del adulto mayor es requerido';
  END IF;

  IF EXISTS (SELECT 1 FROM older_adult WHERE oa_identification = p_oa_identification) THEN
    RAISE EXCEPTION 'Ya existe un adulto mayor con la identificación: %', p_oa_identification;
  END IF;

  IF p_program_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM programs WHERE id = p_program_id) THEN
    RAISE EXCEPTION 'El programa con ID % no existe', p_program_id;
  END IF;

  IF p_pf_identification IS NULL OR btrim(p_pf_identification) = '' THEN
    RAISE EXCEPTION 'La identificación del familiar es requerida';
  END IF;

  IF p_pf_name IS NULL OR btrim(p_pf_name) = '' THEN
    RAISE EXCEPTION 'El nombre del familiar es requerido';
  END IF;

  IF p_pf_email IS NULL OR btrim(p_pf_email) = '' THEN
    RAISE EXCEPTION 'El email del familiar es requerido';
  END IF;

  IF p_pf_s_last_name IS NULL OR btrim(p_pf_s_last_name) = '' THEN
    RAISE EXCEPTION 'El segundo apellido del familiar es requerido';
  END IF;

  INSERT INTO older_adult_family (
    pf_identification, pf_name, pf_f_last_name, pf_s_last_name,
    pf_phone_number, pf_email, pf_kinship
  ) VALUES (
    p_pf_identification, p_pf_name, p_pf_f_last_name, p_pf_s_last_name,
    p_pf_phone_number, p_pf_email, p_pf_kinship
  )
  RETURNING id INTO v_family_id;

  INSERT INTO older_adult (
    oa_identification, oa_name, oa_f_last_name, oa_s_last_name, oa_birthdate,
    oa_marital_status, oa_dwelling, oa_years_schooling, oa_previous_work,
    oa_is_retired, oa_has_pension, oa_other, oa_other_description,
    oa_area_of_origin, oa_children_count, oa_status, oa_death_date,
    oa_economic_income, oa_phone_numner, oa_email, oa_profile_photo_url,
    oa_gender, oa_blood_type, id_program, id_family
  ) VALUES (
    p_oa_identification, p_oa_name, p_oa_f_last_name, p_oa_s_last_name, p_oa_birthdate,
    p_oa_marital_status, p_oa_dwelling, p_oa_years_schooling, p_oa_previous_work,
    p_oa_is_retired, p_oa_has_pension, p_oa_other, p_oa_other_description,
    p_oa_area_of_origin, p_oa_children_count, p_oa_status, p_oa_death_date,
    p_oa_economic_income, p_oa_phone_numner, p_oa_email, p_oa_profile_photo_url,
    p_oa_gender, p_oa_blood_type, p_program_id, v_family_id
  )
  RETURNING id INTO v_older_adult_id;

  INSERT INTO clinical_history (
    ch_frequent_falls, ch_weight, ch_height, ch_imc, ch_blood_pressure,
    ch_neoplasms, ch_neoplasms_description, ch_observations, ch_rcvg,
    ch_vision_problems, ch_vision_hearing, id_older_adult
  ) VALUES (
    p_ch_frequent_falls, p_ch_weight, p_ch_height, p_ch_imc, p_ch_blood_pressure,
    p_ch_neoplasms, p_ch_neoplasms_description, p_ch_observations, p_ch_rcvg,
    p_ch_vision_problems, p_ch_vision_hearing, v_older_adult_id
  )
  RETURNING id INTO v_clinical_history_id;

  -- clinical conditions
  IF p_clinical_conditions_ids IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM unnest(p_clinical_conditions_ids) AS cid
      WHERE NOT EXISTS (SELECT 1 FROM clinical_conditions cc WHERE cc.id = cid)
    ) THEN
      RAISE EXCEPTION 'Alguna de las condiciones clínicas provistas no existe';
    END IF;

    INSERT INTO clinical_history_and_conditions (id_c_condition, id_c_history)
    SELECT cid, v_clinical_history_id
    FROM unnest(p_clinical_conditions_ids) AS cid;
  END IF;

  -- vaccines
  IF p_vaccines_ids IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM unnest(p_vaccines_ids) AS vid
      WHERE NOT EXISTS (SELECT 1 FROM vaccines v WHERE v.id = vid)
    ) THEN
      RAISE EXCEPTION 'Alguna de las vacunas provistas no existe';
    END IF;

    INSERT INTO vaccines_and_clinical_history (id_vaccine, id_c_history)
    SELECT vid, v_clinical_history_id
    FROM unnest(p_vaccines_ids) AS vid;
  END IF;

  -- medications (JSONB array of {medication, dosage, type})
  IF p_medications_json IS NOT NULL AND jsonb_typeof(p_medications_json) = 'array'
     AND jsonb_array_length(p_medications_json) > 0 THEN
    FOR v_med IN SELECT * FROM jsonb_array_elements(p_medications_json)
    LOOP
      INSERT INTO clinical_medication (
        m_medication, m_dosage, m_treatment_type, id_clinical_history
      ) VALUES (
        v_med ->> 'medication',
        v_med ->> 'dosage',
        COALESCE(v_med ->> 'type', 'other')::e_medication_treatment_type,
        v_clinical_history_id
      );
    END LOOP;
  END IF;

  -- sub-programs (must belong to p_program_id when present)
  IF p_subprograms_ids IS NOT NULL THEN
    IF p_program_id IS NULL THEN
      RAISE EXCEPTION 'No se pueden asociar subprogramas sin un programa (id_program)';
    END IF;

    IF EXISTS (
      SELECT 1 FROM unnest(p_subprograms_ids) AS sid
      WHERE NOT EXISTS (
        SELECT 1 FROM sub_programs sp
        WHERE sp.id = sid AND sp.id_program = p_program_id
      )
    ) THEN
      RAISE EXCEPTION 'Alguno de los subprogramas provistos no existe o no pertenece al programa %', p_program_id;
    END IF;

    INSERT INTO older_adult_subprogram (id_older_adult, id_sub_program)
    SELECT v_older_adult_id, sid
    FROM unnest(p_subprograms_ids) AS sid
    ON CONFLICT (id_older_adult, id_sub_program) DO NOTHING;
  END IF;

  RETURN QUERY SELECT
    v_older_adult_id,
    v_family_id,
    v_clinical_history_id,
    'SUCCESS'::TEXT,
    'Expediente virtual creado exitosamente'::TEXT;
END;
$$;

-- -----------------------------------------------------------------------------
-- delete_virtual_file(p_older_adult_identification)
-- Cascades the deletion of an older adult's virtual file. The legacy MySQL
-- version resolved the most recent clinical_history (create_at >= older_adult
-- create_at) and removed the family, the older adult, the clinical history
-- and all related records. This version fixes two safety issues present in
-- the legacy:
--   1) The clinical_history lookup is filtered by id_older_adult (not by
--      create_at) so it can never pick up a row belonging to a different
--      patient.
--   2) ALL clinical_history rows for the older adult are deleted, not just
--      the most recent one. The legacy "MAX(id)" delete left any extra
--      clinical_history rows dangling and would have broken the fk_ch_oa
--      foreign key on the subsequent DELETE FROM older_adult.
-- ON DELETE CASCADE constraints on the M:N relations
-- (clinical_history_and_conditions, vaccines_and_clinical_history) and on
-- clinical_medication take care of the dependent rows automatically.
-- -----------------------------------------------------------------------------
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
  -- The legacy implementation only deleted the MAX(id) row, which left any
  -- additional clinical_history rows dangling and would break the FK
  -- fk_ch_oa on the subsequent DELETE FROM older_adult. The M:N relations
  -- (clinical_history_and_conditions, vaccines_and_clinical_history) and
  -- clinical_medication rows are removed by their ON DELETE CASCADE
  -- constraints.
  DELETE FROM clinical_history WHERE id_older_adult = v_older_adult_id;

  -- Direct deletes (the M:N relations and clinical_medication rows are
  -- removed by ON DELETE CASCADE).
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

-- -----------------------------------------------------------------------------
-- get_virtual_file(p_older_adult_identification)
-- Returns the older adult row joined with the program name, the family row,
-- and a comma-separated list of subprogram names (replaces the legacy
-- GROUP_CONCAT(DISTINCT sp.sp_name)). Raises an exception when the older
-- adult is not found, mirroring the legacy behaviour.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_virtual_file(p_older_adult_identification VARCHAR(20))
RETURNS TABLE (
  oa_id                  INTEGER,
  oa_identification      VARCHAR(20),
  oa_name                VARCHAR(50),
  oa_f_last_name         VARCHAR(50),
  oa_s_last_name         VARCHAR(50),
  oa_birthdate           DATE,
  oa_marital_status      e_oa_marital_status,
  oa_dwelling            TEXT,
  oa_years_schooling     e_oa_years_schooling,
  oa_previous_work       VARCHAR(300),
  oa_is_retired          BOOLEAN,
  oa_has_pension         BOOLEAN,
  oa_other               BOOLEAN,
  oa_other_description   VARCHAR(300),
  oa_area_of_origin      VARCHAR(300),
  oa_children_count      SMALLINT,
  oa_status              e_oa_status,
  oa_death_date          DATE,
  oa_economic_income     NUMERIC(10,2),
  oa_phone_numner        VARCHAR(20),
  oa_email               VARCHAR(256),
  oa_profile_photo_url   VARCHAR(255),
  oa_gender              e_oa_gender,
  oa_blood_type          e_oa_blood_type,
  oa_is_active           BOOLEAN,
  oa_create_at           TIMESTAMPTZ,
  oa_id_program          INTEGER,
  oa_id_family           INTEGER,
  program_name           TEXT,
  pf_id                  INTEGER,
  pf_identification      VARCHAR(20),
  pf_name                VARCHAR(50),
  pf_f_last_name         VARCHAR(50),
  pf_s_last_name         VARCHAR(50),
  pf_phone_number        VARCHAR(20),
  pf_email               VARCHAR(256),
  pf_kinship             e_pf_kinship,
  pf_is_active           BOOLEAN,
  pf_create_at           TIMESTAMPTZ,
  subprograms            TEXT
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_exists BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM older_adult oa WHERE oa.oa_identification = p_older_adult_identification
  ) INTO v_exists;

  IF NOT v_exists THEN
    RAISE EXCEPTION 'No existe un adulto mayor con identificación: %', p_older_adult_identification;
  END IF;

  RETURN QUERY
  SELECT
    oa.id, oa.oa_identification, oa.oa_name, oa.oa_f_last_name, oa.oa_s_last_name,
    oa.oa_birthdate, oa.oa_marital_status, oa.oa_dwelling, oa.oa_years_schooling,
    oa.oa_previous_work, oa.oa_is_retired, oa.oa_has_pension, oa.oa_other,
    oa.oa_other_description, oa.oa_area_of_origin, oa.oa_children_count,
    oa.oa_status, oa.oa_death_date, oa.oa_economic_income, oa.oa_phone_numner,
    oa.oa_email, oa.oa_profile_photo_url, oa.oa_gender, oa.oa_blood_type,
    oa.oa_is_active, oa.create_at, oa.id_program, oa.id_family,
    p.p_name::TEXT                                              AS program_name,
    fam.id                                                      AS pf_id,
    fam.pf_identification, fam.pf_name, fam.pf_f_last_name, fam.pf_s_last_name,
    fam.pf_phone_number, fam.pf_email, fam.pf_kinship,
    fam.pf_is_active, fam.create_at                             AS pf_create_at,
    string_agg(DISTINCT sp.sp_name, ', ' ORDER BY sp.sp_name)::TEXT AS subprograms
  FROM older_adult oa
  LEFT JOIN programs p              ON oa.id_program = p.id
  LEFT JOIN older_adult_family fam  ON oa.id_family  = fam.id
  LEFT JOIN older_adult_subprogram oas ON oa.id     = oas.id_older_adult
  LEFT JOIN sub_programs sp         ON oas.id_sub_program = sp.id
  WHERE oa.oa_identification = p_older_adult_identification
  GROUP BY oa.id, p.p_name, fam.id;
END;
$$;

-- -----------------------------------------------------------------------------
-- compute_audit_session_duration(p_user_id)
-- Mirrors the logout branch of the legacy sp_log_audit: finds the most
-- recent audit_reports row of (login_attempts, login) for the user that has
-- no ar_end_date and returns the number of seconds elapsed since its
-- ar_start_date. Returns 0 if there is no such open login. The application
-- is expected to use this value when writing the logout row (e.g. via
-- log_audit()).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION compute_audit_session_duration(p_user_id INTEGER)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_start_date    TIMESTAMPTZ;
  v_duration_secs INTEGER;
BEGIN
  SELECT ar_start_date
    INTO v_start_date
    FROM audit_reports
   WHERE id_generator = p_user_id
     AND ar_type      = 'login_attempts'
     AND ar_action    = 'login'
     AND ar_end_date  IS NULL
   ORDER BY ar_start_date DESC
   LIMIT 1;

  IF v_start_date IS NULL THEN
    RETURN 0;
  END IF;

  v_duration_secs := GREATEST(0, EXTRACT(EPOCH FROM (NOW() - v_start_date))::INTEGER);
  RETURN v_duration_secs;
END;
$$;

-- End of 009.
