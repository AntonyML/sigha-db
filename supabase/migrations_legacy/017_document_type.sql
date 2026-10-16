-- Add document_type columns to older_adult and older_adult_family
-- Values: 'nacional', 'dimex', 'nite', 'pasaporte'
-- Default 'nacional' preserves existing records

ALTER TABLE older_adult
  ADD COLUMN IF NOT EXISTS oa_document_type VARCHAR(20) NOT NULL DEFAULT 'nacional';

ALTER TABLE older_adult_family
  ADD COLUMN IF NOT EXISTS pf_document_type VARCHAR(20) NOT NULL DEFAULT 'nacional';
