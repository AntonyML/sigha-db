-- =============================================================================
-- 009_role_changes_normalization.sql
-- Normalize role_changes by adding nullable role_id foreign keys while
-- preserving the legacy rc_old_role / rc_new_role text columns.
-- Idempotent: safe to run on a populated database and safe to re-run.
-- Run after 008.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Add nullable role_id columns (preserves all existing rows).
-- -----------------------------------------------------------------------------
ALTER TABLE role_changes
  ADD COLUMN IF NOT EXISTS old_role_id INTEGER;

ALTER TABLE role_changes
  ADD COLUMN IF NOT EXISTS new_role_id INTEGER;

-- -----------------------------------------------------------------------------
-- 2. Backfill: resolve legacy role names to role ids.
--    Only updates rows where the FK is still NULL (idempotent).
--    Rows whose rc_old_role / rc_new_role does not match any current
--    r_name are left with NULL on the new column (never fails).
-- -----------------------------------------------------------------------------
UPDATE role_changes rc
   SET old_role_id = r.id
  FROM roles r
 WHERE rc.old_role_id IS NULL
   AND r.r_name::text = rc.rc_old_role;

UPDATE role_changes rc
   SET new_role_id = r.id
  FROM roles r
 WHERE rc.new_role_id IS NULL
   AND r.r_name::text = rc.rc_new_role;

-- -----------------------------------------------------------------------------
-- 3. Add foreign keys (ON DELETE SET NULL so the audit trail is never lost).
--    Wrapped in DO blocks because PostgreSQL has no ADD CONSTRAINT IF NOT EXISTS.
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'fk_rolechange_old_role'
       AND conrelid = 'role_changes'::regclass
  ) THEN
    ALTER TABLE role_changes
      ADD CONSTRAINT fk_rolechange_old_role
      FOREIGN KEY (old_role_id) REFERENCES roles (id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'fk_rolechange_new_role'
       AND conrelid = 'role_changes'::regclass
  ) THEN
    ALTER TABLE role_changes
      ADD CONSTRAINT fk_rolechange_new_role
      FOREIGN KEY (new_role_id) REFERENCES roles (id) ON DELETE SET NULL;
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 4. Indexes for join performance on history queries.
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_role_changes_old_role_id
  ON role_changes (old_role_id);

CREATE INDEX IF NOT EXISTS idx_role_changes_new_role_id
  ON role_changes (new_role_id);

-- End of 009.
