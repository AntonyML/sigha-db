-- =============================================================================
-- 019_virtual_file_required_family.sql
-- Alinea create_virtual_file() con el contrato DTO del API
-- (CreateVirtualRecordDirectDto):
--   * Familia completa obligatoria: agrega las validaciones que faltaban
--     (primer apellido y parentesco; la tabla los exige NOT NULL pero la
--     función no los validaba y el fallo llegaba como 500 en vez de 400).
--   * Persiste oa/pf_document_type (migración 017 agregó las columnas pero la
--     función ni las recibía: todo caía a 'nacional' en silencio). Los dos
--     parámetros nuevos van AL FINAL con DEFAULT para no romper llamadas
--     existentes de 48 argumentos.
--   * Validaciones condicionales ("solo si ocupa la información"):
--     oa_other -> descripción, estado fallecido -> fecha de defunción,
--     neoplasias -> descripción.
-- CREATE OR REPLACE: re-ejecutable, no toca 011 ni las tablas.
-- Run after 018.
-- =============================================================================

-- La firma cambia (2 parámetros nuevos al final): CREATE OR REPLACE solo
-- reemplaza cuando la firma coincide, así que se elimina primero la variante
-- de 48 argumentos de 011. El DROP es exacto e idempotente (IF EXISTS); el
-- CREATE posterior usa OR REPLACE para que la re-ejecución sea segura.
DROP FUNCTION IF EXISTS create_virtual_file(
  VARCHAR, VARCHAR, VARCHAR, VARCHAR,
  DATE, e_oa_marital_status, TEXT, e_oa_years_schooling,
  VARCHAR, BOOLEAN, BOOLEAN, BOOLEAN,
  VARCHAR, VARCHAR, VARCHAR, VARCHAR, SMALLINT, e_oa_status,
  DATE, NUMERIC,
  VARCHAR, VARCHAR, VARCHAR,
  e_oa_gender, e_oa_blood_type,
  INTEGER,
  VARCHAR, VARCHAR, VARCHAR, VARCHAR,
  VARCHAR, VARCHAR, e_pf_kinship,
  BOOLEAN, NUMERIC, NUMERIC, NUMERIC,
  VARCHAR, BOOLEAN, VARCHAR, TEXT, e_clinical_rcvg,
  BOOLEAN, BOOLEAN,
  INTEGER[], INTEGER[], INTEGER[], JSONB
);

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
  p_oa_province            VARCHAR(100),
  p_oa_canton              VARCHAR(100),
  p_oa_district            VARCHAR(100),
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

  p_medications_json       JSONB,

  p_oa_document_type       VARCHAR(20) DEFAULT 'nacional',
  p_pf_document_type       VARCHAR(20) DEFAULT 'nacional'
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
  v_oa_document_type    VARCHAR(20);
  v_pf_document_type    VARCHAR(20);
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

  IF p_pf_f_last_name IS NULL OR btrim(p_pf_f_last_name) = '' THEN
    RAISE EXCEPTION 'El primer apellido del familiar es requerido';
  END IF;

  IF p_pf_email IS NULL OR btrim(p_pf_email) = '' THEN
    RAISE EXCEPTION 'El email del familiar es requerido';
  END IF;

  IF p_pf_s_last_name IS NULL OR btrim(p_pf_s_last_name) = '' THEN
    RAISE EXCEPTION 'El segundo apellido del familiar es requerido';
  END IF;

  IF p_pf_kinship IS NULL THEN
    RAISE EXCEPTION 'El parentesco del familiar es requerido';
  END IF;

  -- Tipos de documento: normaliza vacío/nulo a 'nacional', rechaza valores
  -- fuera del catálogo (el API ya valida con IsIn; esto es defensa en
  -- profundidad para llamadas SQL directas).
  v_oa_document_type := COALESCE(NULLIF(btrim(p_oa_document_type), ''), 'nacional');
  v_pf_document_type := COALESCE(NULLIF(btrim(p_pf_document_type), ''), 'nacional');

  IF v_oa_document_type NOT IN ('nacional', 'dimex', 'nite', 'pasaporte') THEN
    RAISE EXCEPTION 'Tipo de documento del adulto mayor inválido: %', v_oa_document_type;
  END IF;

  IF v_pf_document_type NOT IN ('nacional', 'dimex', 'nite', 'pasaporte') THEN
    RAISE EXCEPTION 'Tipo de documento del familiar inválido: %', v_pf_document_type;
  END IF;

  -- Condicionales: solo se exigen cuando la información aplica.
  IF p_oa_other IS TRUE
     AND (p_oa_other_description IS NULL OR btrim(p_oa_other_description) = '') THEN
    RAISE EXCEPTION 'La descripción de otros ingresos es requerida cuando se indica otro ingreso';
  END IF;

  IF p_oa_status = 'dead'::e_oa_status AND p_oa_death_date IS NULL THEN
    RAISE EXCEPTION 'La fecha de defunción es requerida cuando el estado es fallecido';
  END IF;

  IF p_ch_neoplasms IS TRUE
     AND (p_ch_neoplasms_description IS NULL OR btrim(p_ch_neoplasms_description) = '') THEN
    RAISE EXCEPTION 'La descripción de neoplasias es requerida cuando se indican neoplasias';
  END IF;

  INSERT INTO older_adult_family (
    pf_identification, pf_document_type, pf_name, pf_f_last_name, pf_s_last_name,
    pf_phone_number, pf_email, pf_kinship
  ) VALUES (
    p_pf_identification, v_pf_document_type, p_pf_name, p_pf_f_last_name, p_pf_s_last_name,
    p_pf_phone_number, p_pf_email, p_pf_kinship
  )
  RETURNING id INTO v_family_id;

  INSERT INTO older_adult (
    oa_identification, oa_document_type, oa_name, oa_f_last_name, oa_s_last_name, oa_birthdate,
    oa_marital_status, oa_dwelling, oa_years_schooling, oa_previous_work,
    oa_is_retired, oa_has_pension, oa_other, oa_other_description,
    oa_province, oa_canton, oa_district, oa_children_count, oa_status, oa_death_date,
    oa_economic_income, oa_phone_numner, oa_email, oa_profile_photo_url,
    oa_gender, oa_blood_type, id_program, id_family
  ) VALUES (
    p_oa_identification, v_oa_document_type, p_oa_name, p_oa_f_last_name, p_oa_s_last_name, p_oa_birthdate,
    p_oa_marital_status, p_oa_dwelling, p_oa_years_schooling, p_oa_previous_work,
    p_oa_is_retired, p_oa_has_pension, p_oa_other, p_oa_other_description,
    p_oa_province, p_oa_canton, p_oa_district, p_oa_children_count, p_oa_status, p_oa_death_date,
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

-- End of 019.
