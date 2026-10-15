-- SIGHA clinical integrity, tenant isolation and shared care model.
-- Apply after 025. Existing residents and their records are assigned to ASOPOGUA.
-- Never edit 021-025: they may already be deployed.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sigha_app') THEN
    CREATE ROLE sigha_app NOLOGIN NOSUPERUSER NOBYPASSRLS NOINHERIT;
  ELSE
    ALTER ROLE sigha_app NOLOGIN NOSUPERUSER NOBYPASSRLS NOINHERIT;
  END IF;
END;
$$;
GRANT sigha_app TO CURRENT_USER;

GRANT USAGE ON SCHEMA public TO sigha_app;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM sigha_app;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM sigha_app;

INSERT INTO public.organizations (name, slug)
VALUES ('ASOPOGUA', 'asopogua')
ON CONFLICT (slug) DO NOTHING;

-- Rename before adding tenant columns so reruns operate on canonical base tables, not compatibility views.
DO $$
BEGIN
  IF to_regclass('public.resident_rooms') IS NULL THEN
    ALTER TABLE public.facility_rooms RENAME TO resident_rooms;
  END IF;
  IF to_regclass('public.resident_stays') IS NULL THEN
    ALTER TABLE public.patient_bed_assignments RENAME TO resident_stays;
  END IF;
  IF to_regclass('public.health_lifestyle') IS NULL THEN
    ALTER TABLE public.patient_lifestyle_assessments RENAME TO health_lifestyle;
  END IF;
END;
$$;

-- Tenant ids stay INTEGER because organizations, residents and users use INTEGER keys.
DO $$
DECLARE
  v_tenant_id INTEGER;
  v_table TEXT;
  v_tables TEXT[] := ARRAY[
    'entrances_exits', 'digital_record', 'audit_reports', 'notifications',
    'notification_attachment', 'role_changes', 'programs', 'sub_programs',
    'older_adult', 'older_adult_family',
    'older_adult_updates', 'emergency_contacts', 'clinical_history',
    'clinical_medication', 'specialized_appointment', 'nursing_records',
    'physiotherapy_sessions', 'psychology_sessions', 'social_work_reports',
    'medical_record', 'patient_conditions', 'medication_prescriptions',
    'medication_administrations', 'patient_vaccinations', 'resident_rooms',
    'resident_stays', 'clinical_encounters', 'clinical_vital_signs',
    'nursing_rounds', 'clinical_note_addendums', 'physiotherapy_evaluations',
    'psychology_evaluations', 'social_work_evaluations',
    'health_lifestyle', 'resident_memos', 'resident_memo_acknowledgments'
  ];
BEGIN
  SELECT id INTO v_tenant_id FROM public.organizations WHERE slug = 'asopogua';
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'The ASOPOGUA organization is required before migration 026';
  END IF;

  FOREACH v_table IN ARRAY v_tables LOOP
    IF to_regclass(format('public.%I', v_table)) IS NULL THEN
    RAISE EXCEPTION 'Migration 026 expected public.% to exist', v_table;
    END IF;
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS tenant_id INTEGER', v_table);
    IF v_table = 'resident_memo_acknowledgments' THEN
      EXECUTE 'UPDATE public.resident_memo_acknowledgments acknowledgment
        SET tenant_id = memo.tenant_id
        FROM public.resident_memos memo
        WHERE acknowledgment.memo_id = memo.id
          AND acknowledgment.tenant_id IS DISTINCT FROM memo.tenant_id';
    END IF;
    EXECUTE format('UPDATE public.%I SET tenant_id = $1 WHERE tenant_id IS NULL', v_table)
      USING v_tenant_id;
    EXECUTE format('ALTER TABLE public.%I ALTER COLUMN tenant_id SET NOT NULL', v_table);
    IF v_table = 'resident_memos' THEN
      ALTER TABLE public.resident_memos
        DROP CONSTRAINT IF EXISTS resident_memos_tenant_id_fkey;
    END IF;
    EXECUTE format(
      'ALTER TABLE public.%I ALTER COLUMN tenant_id SET DEFAULT NULLIF(current_setting(''app.current_tenant_id'',true),'''')::INTEGER',
      v_table
    );
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conrelid = format('public.%I', v_table)::regclass
        AND conname = format('fk_%s_tenant', v_table)
    ) THEN
      EXECUTE format(
        'ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (tenant_id) REFERENCES public.organizations(id) ON DELETE RESTRICT',
        v_table, format('fk_%s_tenant', v_table)
      );
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conrelid = format('public.%I', v_table)::regclass
        AND conname = format('uq_%s_tenant_id', v_table)
    ) THEN
      EXECUTE format(
        'ALTER TABLE public.%I ADD CONSTRAINT %I UNIQUE (tenant_id, id)',
        v_table, format('uq_%s_tenant_id', v_table)
      );
    END IF;
  END LOOP;
END;
$$;

-- These legacy many-to-many tables use composite primary keys instead of an id column.
-- Give each one a tenant key and preserve that composite identity per organization.
DO $$
DECLARE
  v_join RECORD;
  v_tenant_id INTEGER;
BEGIN
  SELECT id INTO v_tenant_id FROM public.organizations WHERE slug = 'asopogua';
  FOR v_join IN
    SELECT * FROM (VALUES
      ('older_adult_subprogram', 'id_older_adult, id_sub_program', 'uq_oasub_tenant_pk'),
      ('clinical_history_and_conditions', 'id_c_condition, id_c_history', 'uq_chc_tenant_pk'),
      ('vaccines_and_clinical_history', 'id_vaccine, id_c_history', 'uq_vch_tenant_pk')
    ) AS joins(table_name, key_columns, unique_constraint)
  LOOP
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS tenant_id INTEGER', v_join.table_name);
    EXECUTE format('UPDATE public.%I SET tenant_id = $1 WHERE tenant_id IS NULL', v_join.table_name)
      USING v_tenant_id;
    EXECUTE format(
      'ALTER TABLE public.%I ALTER COLUMN tenant_id SET DEFAULT NULLIF(current_setting(''app.current_tenant_id'',true),'''')::INTEGER',
      v_join.table_name
    );
    EXECUTE format('ALTER TABLE public.%I ALTER COLUMN tenant_id SET NOT NULL', v_join.table_name);
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conrelid = format('public.%I', v_join.table_name)::regclass
        AND conname = format('fk_%s_tenant', v_join.table_name)
    ) THEN
      EXECUTE format(
        'ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (tenant_id) REFERENCES public.organizations(id) ON DELETE RESTRICT',
        v_join.table_name, format('fk_%s_tenant', v_join.table_name)
      );
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conrelid = format('public.%I', v_join.table_name)::regclass
        AND conname = v_join.unique_constraint
    ) THEN
      EXECUTE format(
        'ALTER TABLE public.%I ADD CONSTRAINT %I UNIQUE (tenant_id, %s)',
        v_join.table_name, v_join.unique_constraint, v_join.key_columns
      );
    END IF;
  END LOOP;
END;
$$;

-- Old scheduled rows were planning placeholders, not completed medication events.
-- Preserve them for traceability, then remove them from the event table.
CREATE TABLE IF NOT EXISTS public.medication_administration_schedule_archive (
  id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  tenant_id INTEGER NOT NULL DEFAULT NULLIF(current_setting('app.current_tenant_id',true),'')::INTEGER
    REFERENCES public.organizations(id) ON DELETE RESTRICT,
  legacy_administration_id INTEGER NOT NULL,
  id_prescription INTEGER NOT NULL,
  id_older_adult INTEGER NOT NULL,
  scheduled_time TIMESTAMPTZ NOT NULL,
  administered_time TIMESTAMPTZ,
  prior_status TEXT NOT NULL,
  dose_given VARCHAR(100),
  administered_by INTEGER,
  omission_reason TEXT,
  observations TEXT,
  created_at TIMESTAMPTZ NOT NULL,
  archived_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  archive_reason TEXT NOT NULL DEFAULT 'Unconfirmed scheduled placeholder archived by migration 026',
  UNIQUE (tenant_id,id),
  UNIQUE (tenant_id,legacy_administration_id),
  FOREIGN KEY (tenant_id,id_prescription)
    REFERENCES public.medication_prescriptions(tenant_id,id) ON DELETE RESTRICT,
  FOREIGN KEY (tenant_id,id_older_adult)
    REFERENCES public.older_adult(tenant_id,id) ON DELETE RESTRICT
);
INSERT INTO public.medication_administration_schedule_archive
  (tenant_id,legacy_administration_id,id_prescription,id_older_adult,scheduled_time,
   administered_time,prior_status,dose_given,administered_by,omission_reason,
   observations,created_at)
SELECT tenant_id,id,id_prescription,id_older_adult,scheduled_time,administered_time,
       status::text,dose_given,administered_by,omission_reason,observations,created_at
FROM public.medication_administrations
WHERE status = 'scheduled' AND administered_time IS NULL
ON CONFLICT (tenant_id,legacy_administration_id) DO NOTHING;
DELETE FROM public.medication_administrations
WHERE status = 'scheduled' AND administered_time IS NULL;
UPDATE public.medication_administrations
SET status = 'administered'
WHERE status = 'scheduled' AND administered_time IS NOT NULL;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.medication_administrations'::regclass AND conname='ck_medication_administrations_no_scheduled_event') THEN
    ALTER TABLE public.medication_administrations ADD CONSTRAINT ck_medication_administrations_no_scheduled_event
      CHECK (status <> 'scheduled');
  END IF;
END;
$$;
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.medication_administrations
    WHERE scheduled_time IS NOT NULL
    GROUP BY tenant_id,id_prescription,scheduled_time
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'Migration 026 found duplicate medication events for a tenant, prescription and scheduled time; resolve them before applying the unique index';
  END IF;
END;
$$;
CREATE UNIQUE INDEX IF NOT EXISTS uq_medication_administrations_tenant_schedule
  ON public.medication_administrations(tenant_id,id_prescription,scheduled_time)
  WHERE scheduled_time IS NOT NULL;

-- Composite foreign keys prevent a row in one organization from pointing at another's resident.
DO $$
DECLARE
  v_constraint RECORD;
BEGIN
  FOR v_constraint IN
    SELECT * FROM (VALUES
      ('older_adult', 'id_family', 'older_adult_family', 'id', 'fk_oa_family_tenant'),
      ('sub_programs', 'id_program', 'programs', 'id', 'fk_subprogram_program_tenant'),
      ('older_adult_subprogram', 'id_older_adult', 'older_adult', 'id', 'fk_oasub_adult_tenant'),
      ('older_adult_subprogram', 'id_sub_program', 'sub_programs', 'id', 'fk_oasub_subprogram_tenant'),
      ('older_adult_updates', 'id_older_adult', 'older_adult', 'id', 'fk_oau_adult_tenant'),
      ('emergency_contacts', 'id_older_adult', 'older_adult', 'id', 'fk_ec_oa_tenant'),
      ('clinical_history', 'id_older_adult', 'older_adult', 'id', 'fk_ch_oa_tenant'),
      ('clinical_history_and_conditions', 'id_c_history', 'clinical_history', 'id', 'fk_chc_hist_tenant'),
      ('vaccines_and_clinical_history', 'id_c_history', 'clinical_history', 'id', 'fk_vch_hist_tenant'),
      ('resident_memos', 'older_adult_id', 'older_adult', 'id', 'fk_resident_memo_adult_tenant'),
      ('resident_memos', 'parent_memo_id', 'resident_memos', 'id', 'fk_resident_memo_parent_tenant'),
      ('resident_memo_acknowledgments', 'memo_id', 'resident_memos', 'id', 'fk_memo_ack_memo_tenant'),
      ('clinical_medication', 'id_clinical_history', 'clinical_history', 'id', 'fk_cm_ch_tenant'),
      ('specialized_appointment', 'id_patient', 'older_adult', 'id', 'fk_appt_patient_tenant'),
      ('nursing_records', 'id_appointment', 'specialized_appointment', 'id', 'fk_nr_appt_tenant'),
      ('physiotherapy_sessions', 'id_appointment', 'specialized_appointment', 'id', 'fk_ps_appt_tenant'),
      ('psychology_sessions', 'id_appointment', 'specialized_appointment', 'id', 'fk_psy_appt_tenant'),
      ('social_work_reports', 'id_appointment', 'specialized_appointment', 'id', 'fk_sw_appt_tenant'),
      ('medical_record', 'id_older_adult', 'older_adult', 'id', 'fk_mr_oa_tenant'),
      ('medical_record', 'id_appointment', 'specialized_appointment', 'id', 'fk_mr_appt_tenant'),
      ('patient_conditions', 'id_older_adult', 'older_adult', 'id', 'fk_pc_older_adult_tenant'),
      ('medication_prescriptions', 'id_older_adult', 'older_adult', 'id', 'fk_mp_older_adult_tenant'),
      ('medication_administrations', 'id_older_adult', 'older_adult', 'id', 'fk_ma_older_adult_tenant'),
      ('medication_administrations', 'id_prescription', 'medication_prescriptions', 'id', 'fk_ma_prescription_tenant'),
      ('patient_vaccinations', 'id_older_adult', 'older_adult', 'id', 'fk_pv_older_adult_tenant'),
      ('resident_stays', 'id_older_adult', 'older_adult', 'id', 'fk_bed_assignment_adult_tenant'),
      ('resident_stays', 'id_room', 'resident_rooms', 'id', 'fk_bed_assignment_room_tenant'),
      ('clinical_encounters', 'id_older_adult', 'older_adult', 'id', 'fk_encounter_adult_tenant'),
      ('clinical_vital_signs', 'id_older_adult', 'older_adult', 'id', 'fk_vitals_adult_tenant'),
      ('clinical_vital_signs', 'id_encounter', 'clinical_encounters', 'id', 'fk_vitals_encounter_tenant'),
      ('nursing_rounds', 'id_older_adult', 'older_adult', 'id', 'fk_round_adult_tenant'),
      ('clinical_note_addendums', 'id_encounter', 'clinical_encounters', 'id', 'fk_addendum_encounter_tenant'),
      ('physiotherapy_evaluations', 'id_older_adult', 'older_adult', 'id', 'fk_physio_adult_tenant'),
      ('physiotherapy_evaluations', 'id_encounter', 'clinical_encounters', 'id', 'fk_physio_encounter_tenant'),
      ('psychology_evaluations', 'id_older_adult', 'older_adult', 'id', 'fk_psychology_adult_tenant'),
      ('psychology_evaluations', 'id_encounter', 'clinical_encounters', 'id', 'fk_psychology_encounter_tenant'),
      ('social_work_evaluations', 'id_older_adult', 'older_adult', 'id', 'fk_social_work_adult_tenant'),
      ('social_work_evaluations', 'id_encounter', 'clinical_encounters', 'id', 'fk_social_work_encounter_tenant'),
      ('health_lifestyle', 'id_older_adult', 'older_adult', 'id', 'fk_lifestyle_adult_tenant'),
      ('notification_attachment', 'id_notification', 'notifications', 'id', 'fk_attachment_notification_tenant')
    ) AS mappings(child_table, child_column, parent_table, parent_column, constraint_name)
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conrelid = format('public.%I', v_constraint.child_table)::regclass
        AND conname = v_constraint.constraint_name
    ) THEN
      EXECUTE format(
        'ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (tenant_id, %I) REFERENCES public.%I (tenant_id, %I) MATCH SIMPLE',
        v_constraint.child_table, v_constraint.constraint_name,
        v_constraint.child_column, v_constraint.parent_table, v_constraint.parent_column
      );
    END IF;
  END LOOP;
END;
$$;

-- User references on tenant records must point to a member of that same tenant.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.organization_members'::regclass AND conname='uq_organization_members_org_user') THEN
    ALTER TABLE public.organization_members ADD CONSTRAINT uq_organization_members_org_user UNIQUE (organization_id,user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.digital_record'::regclass AND conname='fk_digital_actor_tenant') THEN
    ALTER TABLE public.digital_record ADD CONSTRAINT fk_digital_actor_tenant
      FOREIGN KEY (tenant_id,dr_user_id) REFERENCES public.organization_members(organization_id,user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.audit_reports'::regclass AND conname='fk_audit_generator_tenant') THEN
    ALTER TABLE public.audit_reports ADD CONSTRAINT fk_audit_generator_tenant
      FOREIGN KEY (tenant_id,id_generator) REFERENCES public.organization_members(organization_id,user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.notifications'::regclass AND conname='fk_notification_sender_tenant') THEN
    ALTER TABLE public.notifications ADD CONSTRAINT fk_notification_sender_tenant
      FOREIGN KEY (tenant_id,id_sender) REFERENCES public.organization_members(organization_id,user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.role_changes'::regclass AND conname='fk_role_change_user_tenant') THEN
    ALTER TABLE public.role_changes ADD CONSTRAINT fk_role_change_user_tenant
      FOREIGN KEY (tenant_id,id_user) REFERENCES public.organization_members(organization_id,user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.role_changes'::regclass AND conname='fk_role_change_actor_tenant') THEN
    ALTER TABLE public.role_changes ADD CONSTRAINT fk_role_change_actor_tenant
      FOREIGN KEY (tenant_id,changed_by) REFERENCES public.organization_members(organization_id,user_id);
  END IF;
END;
$$;

-- Signatures keep the original SOAP contract and mark historical signatures as unverified.
ALTER TABLE public.clinical_encounters
  ADD COLUMN IF NOT EXISTS signature_hash VARCHAR(64),
  ADD COLUMN IF NOT EXISTS signature_version VARCHAR(32);
ALTER TABLE public.clinical_encounters ALTER COLUMN status DROP DEFAULT;
ALTER TABLE public.clinical_encounters
  ALTER COLUMN status TYPE VARCHAR(32) USING status::text;
ALTER TABLE public.clinical_encounters ALTER COLUMN status SET DEFAULT 'scheduled';
UPDATE public.clinical_encounters
SET status = 'signed', signature_version = 'legacy-unverified'
WHERE is_signed = TRUE AND status <> 'signed';
UPDATE public.clinical_encounters
SET signature_version = 'legacy-unverified'
WHERE status = 'signed' AND signature_version IS NULL;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.clinical_encounters'::regclass AND conname='ck_clinical_encounters_signed_state') THEN
    ALTER TABLE public.clinical_encounters ADD CONSTRAINT ck_clinical_encounters_signed_state
      CHECK ((status = 'signed') = is_signed);
  END IF;
END;
$$;
ALTER TABLE public.clinical_encounters
  ADD COLUMN IF NOT EXISTS specialty_payload JSONB NOT NULL DEFAULT '{}'::JSONB,
  ADD COLUMN IF NOT EXISTS legacy_source_table TEXT,
  ADD COLUMN IF NOT EXISTS legacy_source_id INTEGER;
CREATE UNIQUE INDEX IF NOT EXISTS uq_encounters_legacy_source
  ON public.clinical_encounters(legacy_source_table,legacy_source_id)
  WHERE legacy_source_table IS NOT NULL AND legacy_source_id IS NOT NULL;

ALTER TABLE public.clinical_note_addendums
  ADD COLUMN IF NOT EXISTS signed_by INTEGER,
  ADD COLUMN IF NOT EXISTS signature_hash VARCHAR(64),
  ADD COLUMN IF NOT EXISTS signature_version VARCHAR(32),
  ADD COLUMN IF NOT EXISTS status VARCHAR(16) NOT NULL DEFAULT 'signed';
UPDATE public.clinical_note_addendums
SET signed_by = author_id,
    signature_version = 'legacy-unverified'
WHERE signature_version IS NULL;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.clinical_note_addendums'::regclass AND conname='fk_addendums_signed_by') THEN
    ALTER TABLE public.clinical_note_addendums ADD CONSTRAINT fk_addendums_signed_by
      FOREIGN KEY (signed_by) REFERENCES public.users(id) ON DELETE RESTRICT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.clinical_note_addendums'::regclass AND conname='ck_clinical_note_addendums_signed') THEN
    ALTER TABLE public.clinical_note_addendums ADD CONSTRAINT ck_clinical_note_addendums_signed CHECK (status = 'signed');
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.prevent_signed_encounter_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.is_signed OR OLD.status = 'signed' THEN
      RAISE EXCEPTION 'Signed clinical encounter % is immutable', OLD.id
        USING ERRCODE = '55000';
    END IF;
    RETURN OLD;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF OLD.is_signed OR OLD.status = 'signed' THEN
      RAISE EXCEPTION 'Signed clinical encounter % is immutable', OLD.id
        USING ERRCODE = '55000';
    END IF;
  END IF;

  IF NEW.is_signed OR NEW.status = 'signed' THEN
    IF NOT NEW.is_signed OR NEW.status <> 'signed'
       OR NEW.signed_at IS NULL OR NEW.signed_by IS NULL
       OR NEW.signature_hash IS NULL OR NEW.signature_hash !~ '^[0-9a-f]{64}$'
       OR NEW.signature_version = 'legacy-unverified' THEN
      RAISE EXCEPTION 'A signed encounter requires complete signature metadata and a SHA-256 hash'
        USING ERRCODE = '23514';
    END IF;
    NEW.signature_version := COALESCE(NEW.signature_version, '1');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_signed_encounter_mutation ON public.clinical_encounters;
CREATE TRIGGER trg_prevent_signed_encounter_mutation
  BEFORE INSERT OR UPDATE OR DELETE ON public.clinical_encounters
  FOR EACH ROW EXECUTE FUNCTION public.prevent_signed_encounter_mutation();

CREATE OR REPLACE FUNCTION public.prevent_signed_addendum_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'signed' OR NEW.signed_by IS NULL OR NEW.signed_at IS NULL
       OR NEW.signature_hash IS NULL OR NEW.signature_hash !~ '^[0-9a-f]{64}$'
       OR NEW.signature_version = 'legacy-unverified' THEN
      RAISE EXCEPTION 'A signed addendum requires complete signature metadata and a SHA-256 hash'
        USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.clinical_encounters encounter
      WHERE encounter.tenant_id = NEW.tenant_id
        AND encounter.id = NEW.id_encounter
        AND encounter.is_signed
        AND encounter.status = 'signed'
    ) THEN
      RAISE EXCEPTION 'A signed addendum must reference a signed encounter in the same tenant'
        USING ERRCODE = '23514';
    END IF;
    NEW.signature_version := COALESCE(NEW.signature_version, '1');
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'Signed clinical note addendum % is immutable', OLD.id
    USING ERRCODE = '55000';
END;
$$;
DROP TRIGGER IF EXISTS trg_prevent_signed_addendum_mutation ON public.clinical_note_addendums;
CREATE TRIGGER trg_prevent_signed_addendum_mutation
  BEFORE INSERT OR UPDATE OR DELETE ON public.clinical_note_addendums
  FOR EACH ROW EXECUTE FUNCTION public.prevent_signed_addendum_mutation();

-- Preserve existing discipline records as encounters without fabricating SOAP narratives.
INSERT INTO public.clinical_encounters
  (tenant_id,id_older_adult,id_professional,encounter_type,status,start_time,end_time,specialty_payload,legacy_source_table,legacy_source_id)
SELECT e.tenant_id,e.id_older_adult,e.evaluator_id,'physiotherapy','completed',e.evaluation_date,e.evaluation_date,
  to_jsonb(e)-ARRAY['id','tenant_id','id_older_adult','id_encounter','evaluator_id','evaluation_date','created_at'],
  'physiotherapy_evaluations',e.id
FROM public.physiotherapy_evaluations e WHERE e.id_encounter IS NULL
  ON CONFLICT (legacy_source_table,legacy_source_id)
    WHERE legacy_source_table IS NOT NULL AND legacy_source_id IS NOT NULL DO NOTHING;
UPDATE public.physiotherapy_evaluations e SET id_encounter=c.id
FROM public.clinical_encounters c
WHERE e.id_encounter IS NULL AND c.legacy_source_table='physiotherapy_evaluations' AND c.legacy_source_id=e.id;

INSERT INTO public.clinical_encounters
  (tenant_id,id_older_adult,id_professional,encounter_type,status,start_time,end_time,specialty_payload,legacy_source_table,legacy_source_id)
SELECT e.tenant_id,e.id_older_adult,e.evaluator_id,'psychology','completed',e.evaluation_date,e.evaluation_date,
  to_jsonb(e)-ARRAY['id','tenant_id','id_older_adult','id_encounter','evaluator_id','evaluation_date','created_at'],
  'psychology_evaluations',e.id
FROM public.psychology_evaluations e WHERE e.id_encounter IS NULL
  ON CONFLICT (legacy_source_table,legacy_source_id)
    WHERE legacy_source_table IS NOT NULL AND legacy_source_id IS NOT NULL DO NOTHING;
UPDATE public.psychology_evaluations e SET id_encounter=c.id
FROM public.clinical_encounters c
WHERE e.id_encounter IS NULL AND c.legacy_source_table='psychology_evaluations' AND c.legacy_source_id=e.id;

INSERT INTO public.clinical_encounters
  (tenant_id,id_older_adult,id_professional,encounter_type,status,start_time,end_time,specialty_payload,legacy_source_table,legacy_source_id)
SELECT e.tenant_id,e.id_older_adult,e.evaluator_id,'social_work','completed',e.evaluation_date,e.evaluation_date,
  to_jsonb(e)-ARRAY['id','tenant_id','id_older_adult','id_encounter','evaluator_id','evaluation_date','created_at'],
  'social_work_evaluations',e.id
FROM public.social_work_evaluations e WHERE e.id_encounter IS NULL
  ON CONFLICT (legacy_source_table,legacy_source_id)
    WHERE legacy_source_table IS NOT NULL AND legacy_source_id IS NOT NULL DO NOTHING;
UPDATE public.social_work_evaluations e SET id_encounter=c.id
FROM public.clinical_encounters c
WHERE e.id_encounter IS NULL AND c.legacy_source_table='social_work_evaluations' AND c.legacy_source_id=e.id;

-- Keep one shared scale model; legacy rows retain only data that was actually recorded.
CREATE TABLE IF NOT EXISTS public.clinical_scale_evaluations (
  id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  tenant_id INTEGER NOT NULL DEFAULT NULLIF(current_setting('app.current_tenant_id',true),'')::INTEGER REFERENCES public.organizations(id) ON DELETE RESTRICT,
  encounter_id INTEGER,
  nursing_round_id INTEGER,
  id_older_adult INTEGER NOT NULL,
  scale_type VARCHAR(32) NOT NULL CHECK (scale_type IN ('BARTHEL','YESAVAGE','PFEIFFER','APGAR_FAMILIAR','EVA','GLASGOW')),
  total_score NUMERIC(7,2) NOT NULL,
  interpretation VARCHAR(200) NOT NULL,
  responses_payload JSONB NOT NULL,
  evaluated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  evaluated_by INTEGER REFERENCES public.users(id) ON DELETE SET NULL,
  UNIQUE (tenant_id,id),
  CONSTRAINT ck_scale_evaluation_parent CHECK (encounter_id IS NOT NULL OR nursing_round_id IS NOT NULL),
  CONSTRAINT fk_scale_eval_adult_tenant FOREIGN KEY (tenant_id, id_older_adult)
    REFERENCES public.older_adult(tenant_id, id),
  CONSTRAINT fk_scale_eval_encounter_tenant FOREIGN KEY (tenant_id, encounter_id)
    REFERENCES public.clinical_encounters(tenant_id, id),
  CONSTRAINT fk_scale_eval_round_tenant FOREIGN KEY (tenant_id, nursing_round_id)
    REFERENCES public.nursing_rounds(tenant_id, id)
);
CREATE INDEX IF NOT EXISTS idx_scale_evaluations_adult_date
  ON public.clinical_scale_evaluations(tenant_id, id_older_adult, evaluated_at DESC);

DO $$
BEGIN
  INSERT INTO public.clinical_scale_evaluations
    (tenant_id, encounter_id, id_older_adult, scale_type, total_score, interpretation, responses_payload, evaluated_at, evaluated_by)
  SELECT e.tenant_id, e.id_encounter, e.id_older_adult, 'BARTHEL', e.barthel_total_score,
    e.dependence_level::text,
    jsonb_build_object('legacy', true, 'legacySourceId', e.id, 'items', jsonb_build_object(
      'feeding',e.barthel_feeding,'bathing',e.barthel_bathing,'grooming',e.barthel_grooming,
      'dressing',e.barthel_dressing,'bowels',e.barthel_bowels,'bladder',e.barthel_bladder,
      'toiletUse',e.barthel_toilet_use,'transfers',e.barthel_transfers,
      'mobility',e.barthel_mobility,'stairs',e.barthel_stairs)), e.evaluation_date, e.evaluator_id
  FROM public.physiotherapy_evaluations e
  WHERE NOT EXISTS (SELECT 1 FROM public.clinical_scale_evaluations s WHERE s.tenant_id=e.tenant_id AND s.scale_type='BARTHEL' AND s.responses_payload->>'legacySourceId'=e.id::text);

  INSERT INTO public.clinical_scale_evaluations
    (tenant_id, encounter_id, id_older_adult, scale_type, total_score, interpretation, responses_payload, evaluated_at, evaluated_by)
  SELECT e.tenant_id, e.id_encounter, e.id_older_adult, 'YESAVAGE', e.yesavage_gds_score,
    COALESCE(e.depression_severity::text, 'legacy interpretation unavailable'),
    jsonb_build_object('legacy', true, 'legacySourceId', e.id, 'responsesUnavailable', true), e.evaluation_date, e.evaluator_id
  FROM public.psychology_evaluations e
  WHERE e.yesavage_gds_score IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.clinical_scale_evaluations s WHERE s.tenant_id=e.tenant_id AND s.scale_type='YESAVAGE' AND s.responses_payload->>'legacySourceId'=e.id::text);

  INSERT INTO public.clinical_scale_evaluations
    (tenant_id, encounter_id, id_older_adult, scale_type, total_score, interpretation, responses_payload, evaluated_at, evaluated_by)
  SELECT e.tenant_id, e.id_encounter, e.id_older_adult, 'PFEIFFER', e.pfeiffer_errors_score,
    COALESCE(e.cognitive_impairment::text, 'legacy interpretation unavailable'),
    jsonb_build_object('legacy', true, 'legacySourceId', e.id, 'responsesUnavailable', true), e.evaluation_date, e.evaluator_id
  FROM public.psychology_evaluations e
  WHERE e.pfeiffer_errors_score IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.clinical_scale_evaluations s WHERE s.tenant_id=e.tenant_id AND s.scale_type='PFEIFFER' AND s.responses_payload->>'legacySourceId'=e.id::text);

  INSERT INTO public.clinical_scale_evaluations
    (tenant_id, encounter_id, id_older_adult, scale_type, total_score, interpretation, responses_payload, evaluated_at, evaluated_by)
  SELECT e.tenant_id, e.id_encounter, e.id_older_adult, 'APGAR_FAMILIAR', e.apgar_total_score,
    e.family_functioning::text,
    jsonb_build_object('legacy', true, 'legacySourceId', e.id, 'items', jsonb_build_object(
      'adaptation',e.apgar_adaptation,'partnership',e.apgar_partnership,'growth',e.apgar_growth,
      'affection',e.apgar_affection,'resolve',e.apgar_resolve)), e.evaluation_date, e.evaluator_id
  FROM public.social_work_evaluations e
  WHERE NOT EXISTS (SELECT 1 FROM public.clinical_scale_evaluations s WHERE s.tenant_id=e.tenant_id AND s.scale_type='APGAR_FAMILIAR' AND s.responses_payload->>'legacySourceId'=e.id::text);

  PERFORM setval(
    pg_get_serial_sequence('public.clinical_scale_evaluations','id')::regclass,
    GREATEST(
      COALESCE((SELECT MAX(id) FROM public.clinical_scale_evaluations),0),
      COALESCE((SELECT MAX(id) FROM (
        SELECT id FROM public.physiotherapy_evaluations
        UNION ALL SELECT id FROM public.psychology_evaluations
        UNION ALL SELECT id FROM public.social_work_evaluations
      ) legacy_ids),0),
      1
    ),
    TRUE
  );
END;
$$;

-- Resident stays, beds and pavilions replace the overloaded room assignment model.
CREATE TABLE IF NOT EXISTS public.resident_pavilions (
  id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  tenant_id INTEGER NOT NULL DEFAULT NULLIF(current_setting('app.current_tenant_id',true),'')::INTEGER REFERENCES public.organizations(id) ON DELETE RESTRICT,
  name VARCHAR(100) NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, name)
);
ALTER TABLE public.resident_rooms ADD COLUMN IF NOT EXISTS pavilion_id INTEGER;
CREATE TABLE IF NOT EXISTS public.resident_beds (
  id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  tenant_id INTEGER NOT NULL DEFAULT NULLIF(current_setting('app.current_tenant_id',true),'')::INTEGER REFERENCES public.organizations(id) ON DELETE RESTRICT,
  id_room INTEGER NOT NULL,
  bed_label VARCHAR(20) NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, id_room, bed_label),
  CONSTRAINT fk_resident_beds_room_tenant FOREIGN KEY (tenant_id, id_room)
    REFERENCES public.resident_rooms(tenant_id, id) ON DELETE RESTRICT
);
INSERT INTO public.resident_beds(tenant_id,id_room,bed_label)
SELECT DISTINCT s.tenant_id,s.id_room,s.bed_label FROM public.resident_stays s
ON CONFLICT (tenant_id,id_room,bed_label) DO NOTHING;
ALTER TABLE public.resident_stays ADD COLUMN IF NOT EXISTS id_bed INTEGER;
ALTER TABLE public.resident_stays ADD COLUMN IF NOT EXISTS status VARCHAR(32);
UPDATE public.resident_stays s SET id_bed=b.id
FROM public.resident_beds b
WHERE s.id_bed IS NULL AND b.tenant_id=s.tenant_id AND b.id_room=s.id_room AND b.bed_label=s.bed_label;
UPDATE public.resident_stays SET status = CASE WHEN is_current THEN 'active' ELSE 'discharged' END WHERE status IS NULL;
ALTER TABLE public.resident_stays ALTER COLUMN status SET DEFAULT 'active';
ALTER TABLE public.resident_stays ALTER COLUMN status SET NOT NULL;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.resident_stays'::regclass AND conname='ck_resident_stays_status') THEN
    ALTER TABLE public.resident_stays ADD CONSTRAINT ck_resident_stays_status
      CHECK (status IN ('reserved','active','temporary_absence','discharged','deceased'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.resident_stays'::regclass AND conname='fk_resident_stays_bed_tenant') THEN
    ALTER TABLE public.resident_stays ADD CONSTRAINT fk_resident_stays_bed_tenant
      FOREIGN KEY (tenant_id,id_bed) REFERENCES public.resident_beds(tenant_id,id) ON DELETE RESTRICT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.resident_rooms'::regclass AND conname='fk_resident_rooms_pavilion_tenant') THEN
    ALTER TABLE public.resident_rooms ADD CONSTRAINT fk_resident_rooms_pavilion_tenant
      FOREIGN KEY (tenant_id,pavilion_id) REFERENCES public.resident_pavilions(tenant_id,id) ON DELETE RESTRICT;
  END IF;
END;
$$;
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.resident_stays
    WHERE id_bed IS NOT NULL AND status IN ('reserved','active','temporary_absence')
    GROUP BY tenant_id,id_bed
    HAVING count(DISTINCT id_older_adult) > 1
  ) THEN
    RAISE EXCEPTION 'Migration 026 found different residents assigned to one bed; resolve the occupancy conflict before applying the unique index';
  END IF;
END;
$$;
-- Keep the newest duplicate assignment for the same resident and preserve older rows as discharged history.
WITH duplicate_assignments AS (
  SELECT id,
         row_number() OVER (
           PARTITION BY tenant_id,id_bed
           ORDER BY assigned_at DESC,id DESC
         ) AS assignment_rank
  FROM public.resident_stays
  WHERE id_bed IS NOT NULL AND status IN ('reserved','active','temporary_absence')
)
UPDATE public.resident_stays stay
SET is_current = FALSE,
    status = 'discharged',
    discharged_at = COALESCE(stay.discharged_at,CURRENT_TIMESTAMP)
FROM duplicate_assignments duplicate
WHERE stay.id = duplicate.id
  AND duplicate.assignment_rank > 1;
CREATE UNIQUE INDEX IF NOT EXISTS uq_resident_stays_active_bed
  ON public.resident_stays(tenant_id,id_bed)
  WHERE id_bed IS NOT NULL AND status IN ('reserved','active','temporary_absence');

CREATE TABLE IF NOT EXISTS public.care_programs (
  id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  tenant_id INTEGER NOT NULL DEFAULT NULLIF(current_setting('app.current_tenant_id',true),'')::INTEGER REFERENCES public.organizations(id) ON DELETE RESTRICT,
  name VARCHAR(200) NOT NULL,
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (tenant_id,id), UNIQUE (tenant_id,name)
);
CREATE TABLE IF NOT EXISTS public.care_subprograms (
  id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  tenant_id INTEGER NOT NULL DEFAULT NULLIF(current_setting('app.current_tenant_id',true),'')::INTEGER REFERENCES public.organizations(id) ON DELETE RESTRICT,
  program_id INTEGER NOT NULL,
  name VARCHAR(200) NOT NULL,
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (tenant_id,id), UNIQUE (tenant_id,program_id,name),
  CONSTRAINT fk_care_subprogram_program_tenant FOREIGN KEY (tenant_id,program_id)
    REFERENCES public.care_programs(tenant_id,id) ON DELETE RESTRICT
);
CREATE TABLE IF NOT EXISTS public.resident_program_enrollments (
  id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  tenant_id INTEGER NOT NULL DEFAULT NULLIF(current_setting('app.current_tenant_id',true),'')::INTEGER REFERENCES public.organizations(id) ON DELETE RESTRICT,
  id_older_adult INTEGER NOT NULL,
  subprogram_id INTEGER NOT NULL,
  scale_evaluation_id INTEGER,
  status VARCHAR(16) NOT NULL DEFAULT 'active' CHECK (status IN ('active','completed','cancelled')),
  goals TEXT,
  started_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ended_at TIMESTAMPTZ,
  created_by INTEGER REFERENCES public.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_program_enrollment_adult_tenant FOREIGN KEY (tenant_id,id_older_adult)
    REFERENCES public.older_adult(tenant_id,id),
  CONSTRAINT fk_program_enrollment_subprogram_tenant FOREIGN KEY (tenant_id,subprogram_id)
    REFERENCES public.care_subprograms(tenant_id,id),
  CONSTRAINT fk_program_enrollment_scale_tenant FOREIGN KEY (tenant_id,scale_evaluation_id)
    REFERENCES public.clinical_scale_evaluations(tenant_id,id),
  CHECK (ended_at IS NULL OR ended_at >= started_at)
);

CREATE TABLE IF NOT EXISTS public.access_logs (
  id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  tenant_id INTEGER NOT NULL DEFAULT NULLIF(current_setting('app.current_tenant_id',true),'')::INTEGER REFERENCES public.organizations(id) ON DELETE RESTRICT,
  id_older_adult INTEGER,
  event_type VARCHAR(16) NOT NULL CHECK (event_type IN ('exit','return','visit')),
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expected_return_at TIMESTAMPTZ,
  visitor_name VARCHAR(200),
  notes TEXT,
  recorded_by INTEGER REFERENCES public.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_access_logs_adult_tenant FOREIGN KEY (tenant_id,id_older_adult)
    REFERENCES public.older_adult(tenant_id,id) ON DELETE RESTRICT,
  CHECK (expected_return_at IS NULL OR expected_return_at >= occurred_at)
);

-- A tenant row may reference only a user who is a member of that same tenant.
DO $$
DECLARE
  v_actor RECORD;
BEGIN
  FOR v_actor IN
    SELECT * FROM (VALUES
      ('older_adult_updates', 'changed_by', 'fk_oau_actor_tenant'),
      ('specialized_appointment', 'id_staff', 'fk_appointment_staff_tenant'),
      ('medical_record', 'id_staff', 'fk_medical_record_staff_tenant'),
      ('medication_prescriptions', 'prescribed_by', 'fk_prescription_author_tenant'),
      ('medication_administrations', 'administered_by', 'fk_medication_actor_tenant'),
      ('clinical_encounters', 'id_professional', 'fk_encounter_professional_tenant'),
      ('clinical_encounters', 'signed_by', 'fk_encounter_signer_tenant'),
      ('clinical_vital_signs', 'recorded_by', 'fk_vitals_actor_tenant'),
      ('nursing_rounds', 'id_staff', 'fk_nursing_staff_tenant'),
      ('clinical_note_addendums', 'author_id', 'fk_addendum_author_tenant'),
      ('clinical_note_addendums', 'signed_by', 'fk_addendum_signer_tenant'),
      ('physiotherapy_evaluations', 'evaluator_id', 'fk_physio_evaluator_tenant'),
      ('psychology_evaluations', 'evaluator_id', 'fk_psychology_evaluator_tenant'),
      ('social_work_evaluations', 'evaluator_id', 'fk_social_work_evaluator_tenant'),
      ('health_lifestyle', 'assessed_by', 'fk_lifestyle_assessor_tenant'),
      ('clinical_scale_evaluations', 'evaluated_by', 'fk_scale_evaluator_tenant'),
      ('resident_program_enrollments', 'created_by', 'fk_program_enrollment_actor_tenant'),
      ('resident_memos', 'author_id', 'fk_resident_memo_author_tenant'),
      ('resident_memos', 'target_user_id', 'fk_resident_memo_target_user_tenant'),
      ('resident_memos', 'resolved_by', 'fk_resident_memo_resolver_tenant'),
      ('resident_memo_acknowledgments', 'user_id', 'fk_memo_ack_user_tenant'),
      ('access_logs', 'recorded_by', 'fk_access_log_actor_tenant')
    ) AS actors(table_name, user_column, constraint_name)
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conrelid = format('public.%I', v_actor.table_name)::regclass
        AND conname = v_actor.constraint_name
    ) THEN
      EXECUTE format(
        'ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (tenant_id, %I) REFERENCES public.organization_members(organization_id, user_id) ON DELETE RESTRICT',
        v_actor.table_name, v_actor.constraint_name, v_actor.user_column
      );
    END IF;
  END LOOP;
END;
$$;

CREATE TABLE IF NOT EXISTS public.sys_audit_logs (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id INTEGER NOT NULL DEFAULT NULLIF(current_setting('app.current_tenant_id',true),'')::INTEGER REFERENCES public.organizations(id) ON DELETE RESTRICT,
  table_name TEXT NOT NULL,
  record_id TEXT NOT NULL,
  action VARCHAR(8) NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
  actor_user_id INTEGER REFERENCES public.users(id) ON DELETE SET NULL,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  old_values JSONB,
  new_values JSONB
);
CREATE OR REPLACE FUNCTION public.audit_tenant_row_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_old JSONB;
  v_new JSONB;
  v_tenant_id INTEGER;
  v_record_id TEXT;
  v_actor_id INTEGER;
BEGIN
  IF TG_OP <> 'INSERT' THEN v_old := to_jsonb(OLD); END IF;
  IF TG_OP <> 'DELETE' THEN v_new := to_jsonb(NEW); END IF;
  v_tenant_id := COALESCE((v_new->>'tenant_id')::INTEGER,(v_old->>'tenant_id')::INTEGER);
  v_record_id := COALESCE(v_new->>'id',v_old->>'id',
    CASE TG_TABLE_NAME
      WHEN 'older_adult_subprogram' THEN concat_ws(':', COALESCE(v_new->>'id_older_adult',v_old->>'id_older_adult'), COALESCE(v_new->>'id_sub_program',v_old->>'id_sub_program'))
      WHEN 'clinical_history_and_conditions' THEN concat_ws(':', COALESCE(v_new->>'id_c_condition',v_old->>'id_c_condition'), COALESCE(v_new->>'id_c_history',v_old->>'id_c_history'))
      WHEN 'vaccines_and_clinical_history' THEN concat_ws(':', COALESCE(v_new->>'id_vaccine',v_old->>'id_vaccine'), COALESCE(v_new->>'id_c_history',v_old->>'id_c_history'))
    END);
  v_actor_id := NULLIF(current_setting('app.current_user_id', true),'')::INTEGER;
  INSERT INTO public.sys_audit_logs(tenant_id,table_name,record_id,action,actor_user_id,old_values,new_values)
  VALUES(v_tenant_id,TG_TABLE_NAME,v_record_id,TG_OP,v_actor_id,v_old,v_new);
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.audit_tenant_row_change() FROM PUBLIC;
CREATE OR REPLACE FUNCTION public.prevent_audit_log_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'System audit records are append-only' USING ERRCODE='55000'; END;
$$;
DROP TRIGGER IF EXISTS trg_prevent_sys_audit_mutation ON public.sys_audit_logs;
CREATE TRIGGER trg_prevent_sys_audit_mutation BEFORE UPDATE OR DELETE ON public.sys_audit_logs
FOR EACH ROW EXECUTE FUNCTION public.prevent_audit_log_mutation();

-- Legacy table names remain writable, tenant-aware views for the existing API entity mappings.
CREATE OR REPLACE VIEW public.facility_rooms WITH (security_invoker = true) AS SELECT * FROM public.resident_rooms;
CREATE OR REPLACE VIEW public.patient_bed_assignments WITH (security_invoker = true) AS SELECT * FROM public.resident_stays;
CREATE OR REPLACE VIEW public.patient_lifestyle_assessments WITH (security_invoker = true) AS SELECT * FROM public.health_lifestyle;

DO $$
DECLARE
  v_table TEXT;
  v_tables TEXT[] := ARRAY[
    'entrances_exits','digital_record','audit_reports','notifications','notification_attachment',
    'role_changes','programs','sub_programs',
    'older_adult','older_adult_family','older_adult_subprogram','older_adult_updates',
    'emergency_contacts','clinical_history','clinical_history_and_conditions',
    'vaccines_and_clinical_history','clinical_medication','specialized_appointment',
    'nursing_records','physiotherapy_sessions','psychology_sessions','social_work_reports',
    'medical_record','patient_conditions','medication_prescriptions','medication_administrations',
    'patient_vaccinations','resident_rooms','resident_stays','clinical_encounters',
    'clinical_vital_signs','nursing_rounds','clinical_note_addendums',
    'physiotherapy_evaluations','psychology_evaluations','social_work_evaluations',
    'health_lifestyle','clinical_scale_evaluations','medication_administration_schedule_archive',
    'resident_pavilions','resident_beds','resident_memos','resident_memo_acknowledgments',
    'care_programs','care_subprograms','resident_program_enrollments','access_logs','sys_audit_logs'
  ];
BEGIN
  FOREACH v_table IN ARRAY v_tables LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',v_table);
    EXECUTE format('ALTER TABLE public.%I FORCE ROW LEVEL SECURITY',v_table);
    EXECUTE format('DROP POLICY IF EXISTS tenant_isolation_policy ON public.%I',v_table);
    EXECUTE format(
      'CREATE POLICY tenant_isolation_policy ON public.%I USING (tenant_id = NULLIF(current_setting(''app.current_tenant_id'',true),'''')::INTEGER) WITH CHECK (tenant_id = NULLIF(current_setting(''app.current_tenant_id'',true),'''')::INTEGER)',
      v_table
    );
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON public.%I TO sigha_app',v_table);
    IF EXISTS (
      SELECT 1 FROM pg_attribute
      WHERE attrelid = to_regclass(format('public.%I',v_table))
        AND attname = 'id' AND attnum > 0 AND NOT attisdropped
    ) THEN
      IF pg_get_serial_sequence(format('public.%I',v_table), 'id') IS NOT NULL THEN
        EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE %s TO sigha_app',
          pg_get_serial_sequence(format('public.%I',v_table), 'id'));
      END IF;
    END IF;
    IF v_table <> 'sys_audit_logs' THEN
      EXECUTE format('DROP TRIGGER IF EXISTS trg_audit_tenant_row_change ON public.%I',v_table);
      EXECUTE format(
        'CREATE TRIGGER trg_audit_tenant_row_change AFTER INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.audit_tenant_row_change()',
        v_table
      );
    END IF;
  END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION public.prevent_audit_log_mutation() FROM PUBLIC;

-- Global identities remain global, while tenant requests can read only members of their active organization.
ALTER TABLE public.organization_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_members FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation_policy ON public.organization_members;
CREATE POLICY tenant_isolation_policy ON public.organization_members
  USING (organization_id = NULLIF(current_setting('app.current_tenant_id',true),'')::INTEGER)
  WITH CHECK (organization_id = NULLIF(current_setting('app.current_tenant_id',true),'')::INTEGER);
GRANT SELECT ON public.organization_members TO sigha_app;

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_member_user_read_policy ON public.users;
CREATE POLICY tenant_member_user_read_policy ON public.users FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM public.organization_members member
    WHERE member.user_id = users.id
      AND member.organization_id = NULLIF(current_setting('app.current_tenant_id',true),'')::INTEGER
  ));
GRANT SELECT (id,u_identification,u_name,u_f_last_name,u_s_last_name,u_email,u_email_verified,u_is_active,create_at)
  ON public.users TO sigha_app;
DROP POLICY IF EXISTS tenant_member_user_update_policy ON public.users;
CREATE POLICY tenant_member_user_update_policy ON public.users FOR UPDATE
  USING (EXISTS (
    SELECT 1 FROM public.organization_members member
    WHERE member.user_id = users.id
      AND member.organization_id = NULLIF(current_setting('app.current_tenant_id',true),'')::INTEGER
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.organization_members member
    WHERE member.user_id = users.id
      AND member.organization_id = NULLIF(current_setting('app.current_tenant_id',true),'')::INTEGER
  ));
DROP POLICY IF EXISTS tenant_actor_user_insert_policy ON public.users;
CREATE POLICY tenant_actor_user_insert_policy ON public.users FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.organization_members actor
    WHERE actor.user_id = NULLIF(current_setting('app.current_user_id',true),'')::INTEGER
      AND actor.organization_id = NULLIF(current_setting('app.current_tenant_id',true),'')::INTEGER
  ));
GRANT UPDATE (u_identification,u_name,u_f_last_name,u_s_last_name,u_email,u_email_verified,u_is_active)
  ON public.users TO sigha_app;

CREATE OR REPLACE FUNCTION public.create_tenant_user(
  p_identification TEXT,
  p_name TEXT,
  p_f_last_name TEXT,
  p_s_last_name TEXT,
  p_email TEXT,
  p_password_hash TEXT
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_tenant_id INTEGER := NULLIF(current_setting('app.current_tenant_id',true),'')::INTEGER;
  v_actor_id INTEGER := NULLIF(current_setting('app.current_user_id',true),'')::INTEGER;
  v_user_id INTEGER;
BEGIN
  IF v_tenant_id IS NULL OR v_actor_id IS NULL THEN
    RAISE EXCEPTION 'Tenant and actor context are required to create a user' USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.organization_members member
    JOIN public.organizations org ON org.id = member.organization_id
    WHERE member.organization_id = v_tenant_id AND member.user_id = v_actor_id AND org.is_active
  ) THEN
    RAISE EXCEPTION 'Actor is not an active member of this organization' USING ERRCODE='42501';
  END IF;

  INSERT INTO public.users(u_identification,u_name,u_f_last_name,u_s_last_name,u_email,u_password)
  VALUES(p_identification,p_name,p_f_last_name,p_s_last_name,p_email,p_password_hash)
  RETURNING id INTO v_user_id;

  INSERT INTO public.organization_members(user_id,organization_id,is_primary)
  VALUES(v_user_id,v_tenant_id,TRUE);
  RETURN v_user_id;
END;
$$;

-- Application code cannot fabricate or rewrite audit events; row triggers append as their owner.
REVOKE INSERT, UPDATE, DELETE ON public.sys_audit_logs FROM sigha_app;
REVOKE ALL ON FUNCTION public.create_tenant_user(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_tenant_user(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT) TO sigha_app;

CREATE OR REPLACE FUNCTION public.get_current_user_password_hash(p_user_id INTEGER)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_actor_id INTEGER := NULLIF(current_setting('app.current_user_id',true),'')::INTEGER;
  v_tenant_id INTEGER := NULLIF(current_setting('app.current_tenant_id',true),'')::INTEGER;
  v_password_hash TEXT;
BEGIN
  IF p_user_id IS NULL OR p_user_id <> v_actor_id OR v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'Only the authenticated user may read their password hash' USING ERRCODE='42501';
  END IF;
  SELECT u_password INTO v_password_hash FROM public.users WHERE id=p_user_id
    AND EXISTS (SELECT 1 FROM public.organization_members member
      WHERE member.user_id=p_user_id AND member.organization_id=v_tenant_id);
  IF v_password_hash IS NULL THEN
    RAISE EXCEPTION 'User is not a member of the active organization' USING ERRCODE='42501';
  END IF;
  RETURN v_password_hash;
END;
$$;
REVOKE ALL ON FUNCTION public.get_current_user_password_hash(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_current_user_password_hash(INTEGER) TO sigha_app;

CREATE OR REPLACE FUNCTION public.update_current_user_password(p_user_id INTEGER,p_password_hash TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_actor_id INTEGER := NULLIF(current_setting('app.current_user_id',true),'')::INTEGER;
  v_tenant_id INTEGER := NULLIF(current_setting('app.current_tenant_id',true),'')::INTEGER;
BEGIN
  IF p_user_id IS NULL OR p_user_id <> v_actor_id OR v_tenant_id IS NULL OR p_password_hash IS NULL THEN
    RAISE EXCEPTION 'Only the authenticated user may update their password' USING ERRCODE='42501';
  END IF;
  UPDATE public.users SET u_password=p_password_hash WHERE id=p_user_id
    AND EXISTS (SELECT 1 FROM public.organization_members member
      WHERE member.user_id=p_user_id AND member.organization_id=v_tenant_id);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'User is not a member of the active organization' USING ERRCODE='42501';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.update_current_user_password(INTEGER,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_current_user_password(INTEGER,TEXT) TO sigha_app;

-- Organizations and authorization catalogues remain shared references, with tenant-bounded org settings.
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organizations FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_organization_policy ON public.organizations;
CREATE POLICY tenant_organization_policy ON public.organizations
  USING (id = NULLIF(current_setting('app.current_tenant_id',true),'')::INTEGER)
  WITH CHECK (id = NULLIF(current_setting('app.current_tenant_id',true),'')::INTEGER);
GRANT SELECT ON public.organizations TO sigha_app;
GRANT UPDATE (name,logo_url,updated_at) ON public.organizations TO sigha_app;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.roles, public.permissions, public.role_permissions TO sigha_app;

ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_user_roles_policy ON public.user_roles;
CREATE POLICY tenant_user_roles_policy ON public.user_roles
  USING (EXISTS (
    SELECT 1 FROM public.organization_members member
    WHERE member.user_id = user_roles.user_id
      AND member.organization_id = NULLIF(current_setting('app.current_tenant_id',true),'')::INTEGER
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.organization_members member
    WHERE member.user_id = user_roles.user_id
      AND member.organization_id = NULLIF(current_setting('app.current_tenant_id',true),'')::INTEGER
  ) AND (assigned_by IS NULL OR EXISTS (
    SELECT 1 FROM public.organization_members actor
    WHERE actor.user_id = user_roles.assigned_by
      AND actor.organization_id = NULLIF(current_setting('app.current_tenant_id',true),'')::INTEGER
  )));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_roles TO sigha_app;

ALTER TABLE public.user_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_sessions FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_user_sessions_policy ON public.user_sessions;
CREATE POLICY tenant_user_sessions_policy ON public.user_sessions
  USING (user_id = NULLIF(current_setting('app.current_user_id',true),'')::INTEGER
    AND EXISTS (SELECT 1 FROM public.organization_members member
      WHERE member.user_id = user_sessions.user_id
        AND member.organization_id = NULLIF(current_setting('app.current_tenant_id',true),'')::INTEGER))
  WITH CHECK (user_id = NULLIF(current_setting('app.current_user_id',true),'')::INTEGER
    AND EXISTS (SELECT 1 FROM public.organization_members member
      WHERE member.user_id = user_sessions.user_id
        AND member.organization_id = NULLIF(current_setting('app.current_tenant_id',true),'')::INTEGER));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_sessions TO sigha_app;

ALTER TABLE public.user_two_factor ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_two_factor FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_user_two_factor_policy ON public.user_two_factor;
CREATE POLICY tenant_user_two_factor_policy ON public.user_two_factor
  USING (user_id = NULLIF(current_setting('app.current_user_id',true),'')::INTEGER
    AND EXISTS (SELECT 1 FROM public.organization_members member
      WHERE member.user_id = user_two_factor.user_id
        AND member.organization_id = NULLIF(current_setting('app.current_tenant_id',true),'')::INTEGER))
  WITH CHECK (user_id = NULLIF(current_setting('app.current_user_id',true),'')::INTEGER
    AND EXISTS (SELECT 1 FROM public.organization_members member
      WHERE member.user_id = user_two_factor.user_id
        AND member.organization_id = NULLIF(current_setting('app.current_tenant_id',true),'')::INTEGER));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_two_factor TO sigha_app;

DO $$
DECLARE v_table TEXT; v_sequence TEXT;
BEGIN
  FOREACH v_table IN ARRAY ARRAY['roles','permissions','role_permissions','user_roles','user_sessions','user_two_factor'] LOOP
    IF EXISTS (
      SELECT 1 FROM pg_attribute
      WHERE attrelid = to_regclass(format('public.%I',v_table))
        AND attname = 'id' AND attnum > 0 AND NOT attisdropped
    ) THEN
      v_sequence := pg_get_serial_sequence(format('public.%I',v_table),'id');
      IF v_sequence IS NOT NULL THEN
        EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE %s TO sigha_app',v_sequence);
      END IF;
    END IF;
  END LOOP;
END;
$$;

-- These catalogs contain shared reference data, not resident or organization records.
GRANT SELECT ON public.medication_catalog, public.icd10_catalog, public.specialized_area TO sigha_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.clinical_conditions, public.vaccines TO sigha_app;
DO $$
DECLARE v_table TEXT; v_sequence TEXT;
BEGIN
  FOREACH v_table IN ARRAY ARRAY['clinical_conditions','vaccines'] LOOP
    IF EXISTS (
      SELECT 1 FROM pg_attribute
      WHERE attrelid = to_regclass(format('public.%I',v_table))
        AND attname = 'id' AND attnum > 0 AND NOT attisdropped
    ) THEN
      v_sequence := pg_get_serial_sequence(format('public.%I',v_table),'id');
      IF v_sequence IS NOT NULL THEN
        EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE %s TO sigha_app',v_sequence);
      END IF;
    END IF;
  END LOOP;
  IF to_regclass('public.system_settings') IS NOT NULL THEN
    EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON public.system_settings TO sigha_app';
    IF EXISTS (
      SELECT 1 FROM pg_attribute
      WHERE attrelid = 'public.system_settings'::regclass
        AND attname = 'id' AND attnum > 0 AND NOT attisdropped
    ) THEN
      v_sequence := pg_get_serial_sequence('public.system_settings','id');
      IF v_sequence IS NOT NULL THEN
        EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE %s TO sigha_app',v_sequence);
      END IF;
    END IF;
  END IF;
END;
$$;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.facility_rooms,
  public.patient_bed_assignments, public.patient_lifestyle_assessments TO sigha_app;
