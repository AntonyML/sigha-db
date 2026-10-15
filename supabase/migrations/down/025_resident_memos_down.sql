-- =============================================================================
-- 025_resident_memos_down.sql
-- Reversión de la migración 025 (resident_memos)
-- =============================================================================

DROP TABLE IF EXISTS public.resident_memo_acknowledgments CASCADE;
DROP TABLE IF EXISTS public.resident_memos CASCADE;
DROP FUNCTION IF EXISTS public.trg_set_timestamp_memos() CASCADE;

DROP TYPE IF EXISTS e_memo_category CASCADE;
DROP TYPE IF EXISTS e_memo_urgency CASCADE;
DROP TYPE IF EXISTS e_memo_status CASCADE;
DROP TYPE IF EXISTS e_memo_visibility CASCADE;
