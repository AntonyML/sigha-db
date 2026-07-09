-- Rollback 017_document_type.sql
-- Reverts: ADD COLUMN oa_document_type, ADD COLUMN pf_document_type
-- WARNING: Data in these columns will be lost.

ALTER TABLE older_adult
  DROP COLUMN IF EXISTS oa_document_type;

ALTER TABLE older_adult_family
  DROP COLUMN IF EXISTS pf_document_type;
