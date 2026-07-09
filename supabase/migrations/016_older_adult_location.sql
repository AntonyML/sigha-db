-- Add structured location columns replacing free-text oa_area_of_origin
ALTER TABLE older_adult
  ADD COLUMN IF NOT EXISTS oa_province  VARCHAR(100),
  ADD COLUMN IF NOT EXISTS oa_canton    VARCHAR(100),
  ADD COLUMN IF NOT EXISTS oa_district  VARCHAR(100),
  DROP COLUMN IF EXISTS oa_area_of_origin;